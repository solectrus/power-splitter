require_relative 'reader'

module Flux
  # Reads back the battery ledger balance that was written earlier. Seeding a
  # day from InfluxDB (instead of keeping the balance in memory) is what makes
  # recalculating a day idempotent.
  #
  # Only MAX_AGE is searched. The balance is written for every period that has
  # data, and data stops being carried forward after MAX_AGE - so anything
  # older means there is a gap in the data, and a balance from before a gap says
  # nothing about what the battery did in between. Searching the whole history
  # would only be slower, not more correct.
  class LastState < Flux::Reader
    FIELD = 'battery_energy_grid'.freeze
    public_constant :FIELD

    # Whether the ledger was ever written, searched over the whole history
    # rather than MAX_AGE: this asks which version calculated the records, not
    # what the battery did.
    def written?
      query_string = <<~FLUX
        #{from_bucket}
        |> #{range(start: Time.at(0))}
        |> filter(fn: (r) => r["_measurement"] == "#{config.influx_measurement}" and r["_field"] == "#{FIELD}")
        |> first()
        |> keep(columns: ["_time"])
      FLUX

      query(query_string).any?
    end

    def battery_energy_grid(before:)
      query_string = <<~FLUX
        #{from_bucket}
        |> #{range(start: before - MAX_AGE, stop: before)}
        |> filter(fn: (r) => r["_measurement"] == "#{config.influx_measurement}" and r["_field"] == "#{FIELD}")
        |> last()
      FLUX

      query(query_string).first&.[]('_value')
    end
  end
end
