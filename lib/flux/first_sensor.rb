require_relative 'reader'

module Flux
  # The time of the first reading of any configured sensor at or after `since`,
  # nil if there is none:
  #
  #   first_sensor = Flux::FirstSensor.new(config:)
  #   first_sensor.time                               # => 2020-11-27 10:15:00 +0100
  #   first_sensor.time(since: Time.new(2024, 3, 1))  # => 2024-05-02 08:30:00 +0200
  class FirstSensor < Flux::Reader
    def time(since: Time.at(0))
      query_string = <<~FLUX
        #{from_bucket}
        |> #{range(start: since)}
        |> #{filter}
        |> first()
        |> keep(columns: ["_time"])
        |> min(column: "_time")
      FLUX

      parse_influx_time(query(query_string).first&.[]('_time'))
    end
  end
end
