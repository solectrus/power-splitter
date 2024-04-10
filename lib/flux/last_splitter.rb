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

      result = query(query_string)
      return unless result.first

      result.first.records.first.values['_time']
    end
  end
end
