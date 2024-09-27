require_relative 'reader'

ActiveSupport.to_time_preserves_timezone = true

module Flux
  class Extractor < Flux::Reader
    def records(day)
      range = day_range(day)
      return [] unless range

      query_string = <<~FLUX
        #{from_bucket}
        |> #{range}
        |> #{filter(selected_sensors: config.sensor_names)}
        |> aggregateWindow(every: 1m, fn: mean)
        |> fill(usePrevious: true)
      FLUX
      result = query(query_string)

      extract_and_transform_data(result)
    end

    private

    def day_range(day)
      start = day.beginning_of_day

      stop =
        if day.today?
          current_time = Time.current
          current_time.beginning_of_minute - (current_time.min % 5).minutes
        else
          start + 1.day
        end

      range(start:, stop:) if stop > start
    end

    def extract_and_transform_data(flux_tables)
      results_by_time =
        flux_tables.each_with_object({}) do |table, results|
          table.records.each do |record|
            time = record.values['_time'].to_time
            field = record.values['_field']
            value = record.values['_value']

            results[time] ||= { 'time' => time }
            results[time][field] = value
          end
        end

      results_by_time.values
    end
  end
end
