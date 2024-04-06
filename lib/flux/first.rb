require_relative 'reader'

module Flux
  class First < Flux::Reader
    def time
      query_string = <<~FLUX
        #{from_bucket}
        |> #{range(start: Time.at(0))}
        |> #{filter(selected_sensors: Config::SENSOR_NAMES)}
        |> first()
        |> keep(columns: ["_time"])
        |> min(column: "_time")
      FLUX

      query(query_string).first.records.first.values['_time']
    end
  end
end
