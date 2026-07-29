require_relative 'reader'

module Flux
  class LastSplitter < Flux::Reader
    def time
      query_string = <<~FLUX
        #{from_bucket}
        |> #{range(start: Time.at(0))}
        |> filter(fn: (r) => r["_measurement"] == "#{config.influx_measurement}")
        |> last()
        |> keep(columns: ["_time"])
        |> max(column: "_time")
      FLUX

      parse_influx_time(query(query_string).first&.[]('_time'))
    end
  end
end
