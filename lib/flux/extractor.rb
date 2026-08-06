require_relative 'reader'

module Flux
  # Reads a day of sensor readings out of InfluxDB, for the sensors the config
  # names.
  #
  #   Flux::Extractor.new(config:).records(Date.new(2024, 8, 27))
  #   # => [{ "time"                  => 2024-08-27 00:01:00 +0200,
  #   #       "SENEC:grid_power_plus" => 2500.0,
  #   #       "SENEC:house_power"     => 481.5,
  #   #       "Heatpump:power"        => 0.0 },
  #   #     { "time"                  => 2024-08-27 00:02:00 +0200,
  #   #       "SENEC:grid_power_plus" => 2480.0,
  #   #       "SENEC:house_power"     => 475.0,
  #   #       "Heatpump:power"        => 0.0 },
  #   #     ... ]
  #
  # "time" is an ActiveSupport::TimeWithZone in the configured zone, so the day
  # runs from local midnight although InfluxDB stores UTC. The other keys are
  # "measurement:field" as the config names them, their values floats.
  #
  # One record per minute, in chronological order: a full day gives 1440 of
  # them, stamped 00:01 through the following midnight - 1380 or 1500 where the
  # clocks change. For today, they end at the last completed five-minute mark.
  #
  # Sensors report irregularly, so a reading is carried forward over the minutes
  # that follow it. Where one has been silent for too long the minute is left
  # out rather than filled with a stale value - a record missing is how the
  # consumer tells a gap apart from a slow sensor.
  class Extractor < Flux::Reader
    # The names the two streams are yielded under, and come back under in the
    # "result" column.
    VALUES = 'values'.freeze
    GAPS = 'gaps'.freeze

    # What the two streams are matched on, so both queries have to keep them.
    KEY_COLUMNS = %w[_time _measurement _field].freeze

    private_constant :VALUES, :GAPS, :KEY_COLUMNS

    def records(day)
      start = day.beginning_of_day
      stop = day_stop(day)
      return [] if stop <= start

      # What a minute is worth and whether it is worth anything at all are
      # asked at different resolutions: the value needs the 5s stream, whether
      # it counts only the raw one. Both travel in one request.
      rows = query(values_query(start, stop) + gaps_query(start, stop))
      extract_and_transform_data(within_reach(rows))
    end

    private

    # Keeps the value of every minute a sensor reading still backs. Matched up
    # in Ruby because neither stream reads the other - joining them in Flux
    # measured several times slower.
    #
    # The second stream names the minutes to drop rather than the ones to keep,
    # so most days it is empty and there is nothing to match at all.
    def within_reach(rows)
      values, gaps = rows.partition { it['result'] == VALUES }
      return values if gaps.empty?

      out_of_reach = gaps.to_set { key_of(it) }
      values.reject { out_of_reach.include?(key_of(it)) }
    end

    def key_of(row)
      row.values_at(*KEY_COLUMNS)
    end

    # The rows both queries start from, and they have to be the same rows:
    # `within_reach` matches the two streams on time and sensor.
    #
    # The range starts MAX_AGE before the day so that silence and last value are
    # counted within it; each query drops that lead-in again at the end.
    def source(start, stop)
      <<~FLUX.chomp
        #{from_bucket}
        |> #{range(start: start - MAX_AGE, stop:)}
        |> #{filter}
      FLUX
    end

    # Every minute of every sensor, carried forward without end.
    #
    # The seconds are stamped at the start of the five they stand for, the
    # minutes at the end of the sixty they cover, so both windows are counted
    # from the same instant.
    #
    # Only four columns are kept - the annotations InfluxDB would add otherwise
    # are a third of the CSV, over thousands of rows a day.
    def values_query(start, stop)
      <<~FLUX
        #{source(start, stop)}
        |> aggregateWindow(every: 5s, fn: last, timeSrc: "_start")
        |> fill(usePrevious: true)
        |> aggregateWindow(every: #{RECORD_DURATION.to_i}s, fn: mean)
        |> filter(fn: (r) => exists r._value)
        |> #{lead_in_trim(start)}
        |> keep(columns: #{[*KEY_COLUMNS, '_value'].inspect})
        |> yield(name: "#{VALUES}")
      FLUX
    end

    # The minutes each sensor has fallen out of reach of a reading. Counting per
    # minute rather than per 5s window draws the line in the same place, because
    # MAX_AGE is a whole number of minutes.
    #
    # An empty window arrives as a count of zero, or as nothing before the
    # sensor's first report - `stateDuration` counts both as silence.
    #
    # Asking for the minutes to drop rather than the ones to keep is the same
    # question: both streams are windowed over the same grid, so each is the
    # complement of the other. It is the far smaller half. A day without a gap
    # answers with nothing at all here, where the minutes in reach are a row per
    # sensor and minute - some 12,000 of them, half the answer, carrying no
    # value and existing only to be matched against.
    def gaps_query(start, stop)
      <<~FLUX
        #{source(start, stop)}
        |> aggregateWindow(every: #{RECORD_DURATION.to_i}s, fn: count, createEmpty: true)
        |> stateDuration(fn: (r) => not exists r._value or r._value == 0, column: "silence", unit: 1s)
        |> filter(fn: (r) => r["silence"] >= #{MAX_AGE.to_i})
        |> #{lead_in_trim(start)}
        |> keep(columns: #{KEY_COLUMNS.inspect})
        |> yield(name: "#{GAPS}")
      FLUX
    end

    # A record is stamped at the end of the window it covers, so the first one
    # belonging to the day is stamped a record length past midnight.
    def lead_in_trim(start)
      "filter(fn: (r) => r[\"_time\"] >= #{flux_time(start + RECORD_DURATION)})"
    end

    def day_stop(day)
      return day.beginning_of_day + 1.day unless day.today?

      current_time = Time.current
      current_time.beginning_of_minute - (current_time.min % 5).minutes
    end

    # UTC, so that no offset has to be parsed back.
    def flux_time(time)
      time.utc.iso8601
    end

    def extract_and_transform_data(rows)
      results_by_time =
        rows.each_with_object({}) do |row, results|
          time = parse_influx_time(row['_time'])

          result = (results[time] ||= { 'time' => time })
          result["#{row['_measurement']}:#{row['_field']}"] = row['_value']
        end

      # Gaps are dropped, so the tables span unequal ranges and the hash fills in
      # table order. Consumers integrate record by record, so sort by time.
      results_by_time.values.sort_by { it['time'] }
    end
  end
end
