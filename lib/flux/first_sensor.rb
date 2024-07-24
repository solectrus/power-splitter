require_relative 'reader'

module Flux
  class FirstSensor < Flux::Reader
    def time
      query_string = <<~FLUX
        #{from_bucket}
        |> #{range(start: Time.at(0))}
        |> #{filter(selected_sensors: config.sensor_names)}
        |> first()
        |> keep(columns: ["_time"])
        |> min(column: "_time")
      FLUX

      result = query(query_string)
      return unless result.first

      Time.new result.first.records.first.values['_time']
    end
  end
end
