require 'config'
require 'splitter'

class Processor
  def initialize(day_records:, config:, battery_energy_grid: 0)
    @day_records = day_records
    @config = config
    @battery_energy_grid = battery_energy_grid
  end

  attr_reader :day_records, :config, :battery_energy_grid

  def call
    group_by_period(split_all).map { |elem| point(elem) }
  end

  private

  PERIOD = 5.minutes
  private_constant :PERIOD

  # Length of a single record, as produced by Flux::Extractor
  RECORD_DURATION = 1.minute
  private_constant :RECORD_DURATION

  # The battery ledger carries over from record to record, so the records must
  # be processed in chronological order.
  def split_all
    balance = battery_energy_grid

    day_records.map do |record|
      split_power(record, balance).tap do |splitted|
        balance = splitted[:battery_energy_grid] || balance
      end
    end
  end

  def point(record)
    InfluxDB2::Point
      .new(name: config.influx_measurement, time: record[:time].to_i)
      .tap do |result|
        fields(record).each { |key, value| result.add_field(key.to_s, value) }
      end
  end

  def fields(record)
    record.except(:time)
  end

  # Fields that hold a state rather than a power, so averaging them would be
  # wrong - the value at the end of the period is what carries over.
  STATE_FIELDS = %i[battery_energy_grid].freeze
  private_constant :STATE_FIELDS

  def group_by_period(splitted)
    splitted
      .group_by { |item| (item[:time].to_i - 1.minute) / PERIOD }
      .map do |_interval, items|
        keys = items.flat_map(&:keys).uniq - [:time]

        keys
          .to_h do |key|
            [key, STATE_FIELDS.include?(key) ? last(items, key) : avg(items, key)]
          end
          .merge(time: items.last[:time] - (PERIOD / 2.0))
          .compact
      end
  end

  def avg(items, key)
    return if items.empty? || items.all? { |item| item[key].nil? }

    items.sum { |item| item[key] || 0 }.fdiv(items.size).round
  end

  def last(items, key)
    items.reverse.filter_map { |item| item[key] }.first
  end

  def power_value(record, sensor_name, default = nil)
    identifier = config.identifier(sensor_name)

    record[identifier] || default
  end

  def adjusted_house_power(record)
    result = power_value(record, :house_power, 0)

    if config.exclude_from_house_power.include?(:heatpump_power)
      result -= power_value(record, :heatpump_power, 0)
    end

    if config.exclude_from_house_power.include?(:wallbox_power)
      result -= power_value(record, :wallbox_power, 0)
    end

    config.custom_sensors.each do |sensor|
      next unless config.exclude_from_house_power.include?(sensor)

      result -= power_value(record, sensor, 0)
    end

    [result, 0].max
  end

  def split_power(record, battery_energy_grid)
    Splitter
      .new(
        config,
        grid_import_power: power_value(record, :grid_import_power),
        battery_charging_power: power_value(record, :battery_charging_power),
        battery_discharging_power:
          power_value(record, :battery_discharging_power),
        house_power: adjusted_house_power(record),
        wallbox_power: power_value(record, :wallbox_power),
        heatpump_power: power_value(record, :heatpump_power),
        custom_power:
          config.custom_sensors.map { |sensor| power_value(record, sensor) },
        battery_energy_grid:,
        duration: RECORD_DURATION,
      )
      .call
      .merge(time: record['time'])
  end
end
