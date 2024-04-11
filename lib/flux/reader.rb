require_relative 'base'

module Flux
  class Reader < Flux::Base
    def query(string)
      read_api.query(query: string)
    end

    private

    def from_bucket
      "from(bucket: \"#{config.influx_bucket}\")"
    end

    def filter(selected_sensors: sensors)
      raw =
        selected_sensors.filter_map do |sensor|
          [
            config.measurement(sensor),
            config.field(sensor),
          ].compact
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
