require_relative 'base'

module Flux
  class Writer < Flux::Base
    def push(records)
      write_api.write(data: points(records))
    end

    private

    def points(records)
      records.map do |entry|
        [
          point(entry, tag: 'grid'),
          point(entry, tag: 'pv'),

        ]
      end.flatten
    end

    def point(record, tag:)
      result = InfluxDB2::Point.new(
        name: config.influx_measurement,
        time: record[:time].to_i,
      )

      result.add_tag('origin', tag)
      result.add_field('house_power', record[:"house_power_from_#{tag}"])
      result.add_field('wallbox_power', record[:"wallbox_power_from_#{tag}"])
      result.add_field('heatpump_power', record[:"heatpump_power_from_#{tag}"])

      result
    end
  end
end
