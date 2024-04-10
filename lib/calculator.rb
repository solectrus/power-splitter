require 'config'

class Calculator
  def initialize(day_records:, config:)
    @day_records = day_records
    @config = config
  end

  attr_reader :day_records, :config

  def call
    tagged group_by_hour(
      day_records.reduce([]) do |acc, record|
        acc << split_power(record)
      end,
    )
  end

  private

  def tagged(records)
    records.map do |entry|
      [
        point(entry, tag: 'grid'),
        point(entry, tag: 'pv'),

      ]
    end.flatten
  end

  def point(record, tag:)
    result = InfluxDB2::Point.new(
      name: config.influx_measurement,
      time: record[:time].to_i,
    )

    result.add_tag('origin', tag)
    result.add_field('house_power', record[:"house_power_from_#{tag}"])
    result.add_field('wallbox_power', record[:"wallbox_power_from_#{tag}"])
    result.add_field('heatpump_power', record[:"heatpump_power_from_#{tag}"])

    result
  end

  def group_by_hour(splitted)
    splitted.group_by { |item| item[:time].hour }.map do |_hour, items|
      {
        time: items.first[:time].beginning_of_hour,
        house_power_from_grid: sum(items, :house_power_from_grid),
        house_power_from_pv: sum(items, :house_power_from_pv),
        wallbox_power_from_grid: sum(items, :wallbox_power_from_grid),
        wallbox_power_from_pv: sum(items, :wallbox_power_from_pv),
        heatpump_power_from_grid: sum(items, :heatpump_power_from_grid),
        heatpump_power_from_pv: sum(items, :heatpump_power_from_pv),
      }
    end
  end

  def sum(items, key)
    return 0 if items.empty?

    (items.sum { |item| item[key] } / items.size.to_f).round
  end

  def grid_import_power(record)
    power_value(record, :grid_import_power)
  end

  def house_power(record)
    power_value(record, :house_power)
  end

  def wallbox_power(record)
    power_value(record, :wallbox_power)
  end

  def heatpump_power(record)
    power_value(record, :heatpump_power)
  end

  def power_value(record, sensor_name)
    (record[config.field(sensor_name)] || 0).round
  end

  def total_power(record)
    house_power(record) + wallbox_power(record) + heatpump_power(record)
  end

  def split_power(record) # rubocop:disable Metrics/AbcSize
    house_power = house_power(record)
    wallbox_power = wallbox_power(record)
    heatpump_power = heatpump_power(record)
    total_power = total_power(record)

    grid_import_power = grid_import_power(record)

    house_power_from_grid = 0
    wallbox_power_from_grid = 0
    heatpump_power_from_grid = 0

    unless grid_import_power.zero? || total_power.zero?
      house_power_ratio = house_power.fdiv(total_power)
      wallbox_power_ratio = wallbox_power.fdiv(total_power)
      heatpump_power_ratio = heatpump_power.fdiv(total_power)

      house_power_from_grid = grid_import_power * house_power_ratio
      wallbox_power_from_grid = grid_import_power * wallbox_power_ratio
      heatpump_power_from_grid = grid_import_power * heatpump_power_ratio
    end

    house_power_from_pv = house_power - house_power_from_grid
    wallbox_power_from_pv = wallbox_power - wallbox_power_from_grid
    heatpump_power_from_pv = heatpump_power - heatpump_power_from_grid

    {
      time: record['time'],

      house_power_from_grid:,
      wallbox_power_from_grid:,
      heatpump_power_from_grid:,

      house_power_from_pv:,
      wallbox_power_from_pv:,
      heatpump_power_from_pv:,
    }
  end
end
