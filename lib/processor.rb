require 'config'
require 'splitter'

class Processor
  def initialize(day_records:, config:)
    @day_records = day_records
    @config = config

    @wallbox_present = config.exists?(:wallbox_power)
    @heatpump_present = config.exists?(:heatpump_power)
  end

  attr_reader :day_records, :config, :wallbox_present, :heatpump_present

  def call
    group_by_period(
      day_records.reduce([]) { |acc, elem| acc << split_power(elem) },
    ).map { |elem| point(elem) }
  end

  private

  PERIOD = 5.minutes
  private_constant :PERIOD

  def point(record)
    result =
      InfluxDB2::Point.new(
        name: config.influx_measurement,
        time: record[:time].to_i,
      )

    result.add_field('house_power_grid', record[:house_power_grid])

    if wallbox_present
      result.add_field('wallbox_power_grid', record[:wallbox_power_grid])
    end

    if heatpump_present
      result.add_field('heatpump_power_grid', record[:heatpump_power_grid])
    end

    result
  end

  def group_by_period(splitted)
    splitted
      .group_by { |item| (item[:time].to_i - 1.minute) / PERIOD }
      .map do |_interval, items|
        {
          time: items.last[:time],
          house_power_grid: avg(items, :house_power_grid),
          wallbox_power_grid:
            wallbox_present ? avg(items, :wallbox_power_grid) : nil,
          heatpump_power_grid:
            heatpump_present ? avg(items, :heatpump_power_grid) : nil,
        }.compact
      end
  end

  def avg(items, key)
    return 0 if items.empty?

    items.sum { |item| item[key] }.fdiv(items.size).round
  end

  def grid_import_power(record)
    power_value(record, :grid_import_power)
  end

  def house_power(record)
    power_value(record, :house_power)
  end

  def wallbox_power(record)
    return 0 unless config.exists?(:wallbox_power)

    power_value(record, :wallbox_power)
  end

  def heatpump_power(record)
    return 0 unless config.exists?(:heatpump_power)

    power_value(record, :heatpump_power)
  end

  def battery_charging_power(record)
    return 0 unless config.exists?(:battery_charging_power)

    power_value(record, :battery_charging_power)
  end

  def power_value(record, sensor_name)
    identifier = config.identifier(sensor_name)

    record[identifier] || 0.0
  end

  def split_power(record)
    house_power = house_power(record)
    wallbox_power = wallbox_power(record)
    heatpump_power = heatpump_power(record)

    house_power -= heatpump_power if config.exclude_from_house_power.include?(
      :heatpump_power,
    )
    house_power -= wallbox_power if config.exclude_from_house_power.include?(
      :wallbox_power,
    )
    house_power = [house_power, 0].max

    grid_import_power = grid_import_power(record)
    battery_charging_power = battery_charging_power(record)

    Splitter
      .new(
        grid_import_power:,
        battery_charging_power:,
        house_power:,
        wallbox_power:,
        heatpump_power:,
      )
      .call
      .merge(time: record['time'])
  end
end
