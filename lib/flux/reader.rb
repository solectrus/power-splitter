require_relative 'base'
require_relative 'csv_parser'

module Flux
  class Reader < Flux::Base
    # How far back the battery ledger balance is searched. A balance older than
    # this sits behind a gap in the data, and what the battery did in between
    # is unknown - so it is not a starting point, it is a guess.
    MAX_AGE = 120.minutes
    public_constant :MAX_AGE

    # Returns the result as plain row hashes (column => value), flattened
    # across Flux tables. The raw CSV is parsed here rather than by the client
    # gem - see Flux::CsvParser for why.
    def query(string)
      CsvParser.call(read_api.query_raw(query: string))
    end

    # Parse InfluxDB timestamp and convert to configured timezone.
    #
    # Memoized because a query covering several sensors returns one row per
    # sensor and window, all stamped with the same instant: a day of minute
    # records for eight sensors holds 11,520 rows but only 1,440 distinct
    # timestamps. The cache lives as long as the reader, which is built per
    # query, so it cannot grow past the result it was filled from.
    def parse_influx_time(time_str)
      return unless time_str

      @parsed_times ||= {}
      @parsed_times[time_str] ||= config.time_zone.parse(time_str)
    end

    private

    def from_bucket
      "from(bucket: \"#{config.influx_bucket}\")"
    end

    def filter(selected_sensors: sensors)
      raw =
        selected_sensors.filter_map do |sensor|
          [config.measurement(sensor), config.field(sensor)].compact
        end

      # Build hash: Key is measurement, value is array of fields
      hash = raw.group_by(&:first).transform_values { |v| v.map(&:last) }

      # Build filter string
      filter =
        hash.map do |measurement, fields|
          field_filter =
            fields.map { |field| "r[\"_field\"] == \"#{field}\"" }.join(' or ')

          "r[\"_measurement\"] == \"#{measurement}\" and (#{field_filter})"
        end

      "filter(fn: (r) => #{filter.join(' or ')})"
    end

    def range(start:, stop: nil)
      start = start&.iso8601
      stop = stop&.iso8601

      stop ? "range(start: #{start}, stop: #{stop})" : "range(start: #{start})"
    end
  end
end
