require_relative 'reader'

module Flux
  class FirstSensor < Flux::Reader
    def time
      query_string = <<~FLUX
        #{from_bucket}
        |> #{range(start: Time.at(0))}
        |> #{filter}
        |> first()
        |> keep(columns: ["_time"])
        |> min(column: "_time")
      FLUX

      parse_influx_time(query(query_string).first&.[]('_time'))
    end
  end
end
