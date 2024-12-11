require 'config'
require 'splitter'

class Processor
  def initialize(day_records:, config:)
    @day_records = day_records
    @config = config
  end

  attr_reader :day_records, :config

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

    if record[:wallbox_power_grid]
      result.add_field('wallbox_power_grid', record[:wallbox_power_grid])
    end

    if record[:heatpump_power_grid]
      result.add_field('heatpump_power_grid', record[:heatpump_power_grid])
    end

    config.custom_sensors.each do |sensor|
      key = :"#{sensor}_grid"
      next unless record[key]

      result.add_field(key.to_s, record[key])
    end

    result
  end

  def group_by_period(splitted)
    splitted
      .group_by { |item| (item[:time].to_i - 1.minute) / PERIOD }
      .map do |_interval, items|
        base_data = {
          time: items.last[:time],
          house_power_grid: avg(items, :house_power_grid),
          wallbox_power_grid: avg(items, :wallbox_power_grid),
          heatpump_power_grid: avg(items, :heatpump_power_grid),
        }

        custom_data =
          config.custom_sensors.each.to_h do |sensor|
            key = :"#{sensor}_grid"

            [key, avg(items, key)]
          end

        base_data.merge(custom_data).compact
      end
  end

  def avg(items, key)
    return if items.empty? || items.all? { |item| item[key].nil? }

    items.sum { |item| item[key] || 0 }.fdiv(items.size).round
  end

  def power_value(record, sensor_name, default = nil)
    identifier = config.identifier(sensor_name)

    record[identifier] || default
  end

  def adjusted_house_power(record)
    result = power_value(record, :house_power)

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

  def split_power(record)
    wallbox_power = power_value(record, :wallbox_power)
    heatpump_power = power_value(record, :heatpump_power)
    house_power = adjusted_house_power(record)

    grid_import_power = power_value(record, :grid_import_power)
    battery_charging_power = power_value(record, :battery_charging_power)

    custom_power =
      config.custom_sensors.map { |sensor| power_value(record, sensor) }

    Splitter
      .new(
        config,
        grid_import_power:,
        battery_charging_power:,
        house_power:,
        wallbox_power:,
        heatpump_power:,
        custom_power:,
      )
      .call
      .merge(time: record['time'])
  end
end
