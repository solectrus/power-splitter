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
