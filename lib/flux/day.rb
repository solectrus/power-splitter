require_relative 'reader'

module Flux
  class Day < Flux::Reader
    def records(day)
      query_string = <<~FLUX
        #{from_bucket}
        |> #{day_range(day)}
        |> #{filter(selected_sensors: Config::SENSOR_NAMES)}
        |> aggregateWindow(every: 5m, fn: mean)
      FLUX
      result = query(query_string)
      extract_and_transform_data(result)
    end

    private

    def day_range(day)
      range(start: day.beginning_of_day, stop: [day.beginning_of_day + 1.day, Time.current.beginning_of_hour].min)
    end

    def extract_and_transform_data(flux_tables)
      results_by_time = flux_tables.each_with_object({}) do |table, results|
        table.records.each do |record|
          time = record.values['_time'].to_time
          field = record.values['_field']
          value = record.values['_value']

          results[time] ||= { 'time' => time }
          results[time][field] = value
        end
      end

      results_by_time.values # .sort_by { |h| h['time'] }
    end
  end
end
