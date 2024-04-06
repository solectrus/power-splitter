require_relative 'base'

module Flux
  class Writer < Flux::Base
    def push(records)
      write_api.write(
        data: points(records),
        bucket: config.influx_bucket,
        org: config.influx_org,
      )
    end

    private

    def points(records)
      records.map do |record|
        InfluxDB2::Point.new(
          time: record[:time].to_i,
          name: config.influx_measurement,
          fields: record.except(:time),
        )
      end
    end
  end
end
