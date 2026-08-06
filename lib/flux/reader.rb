require_relative 'base'
require_relative 'csv_parser'

module Flux
  class Reader < Flux::Base
    # The grid the readings are averaged into. Sensors report at their own
    # pace, the result does not: it holds one record per window either way.
    # That is what lets a consumer tell a gap from a slow sensor - a window
    # missing from the result means the data stopped, not that nothing was
    # measured in it.
    RECORD_DURATION = 1.minute
    public_constant :RECORD_DURATION

    # How long a measured value is taken to still describe the present. Sensors
    # report irregularly, so the last value is carried forward to cover the
    # moments in between - but past this, silence means the data stopped rather
    # than the value standing still, and the window is dropped. Also how far
    # back the battery ledger balance is searched.
    MAX_AGE = 120.minutes
    public_constant :MAX_AGE

    # Returns the result as plain row hashes (column => value), flattened across
    # Flux tables and across yields - a multi-yield query tells its streams apart
    # by the "result" column. Parsed here rather than by the client gem - see
    # Flux::CsvParser for why.
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

    def filter(selected_sensors: config.sensor_names)
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
      start = start.iso8601
      stop = stop&.iso8601

      stop ? "range(start: #{start}, stop: #{stop})" : "range(start: #{start})"
    end
  end
end
