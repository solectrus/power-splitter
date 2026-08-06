require 'config'
require 'splitter'
require 'flux/reader'

class Processor
  def initialize(day:, day_records:, config:, battery_energy_grid: 0)
    @day = day
    @day_records = day_records
    @config = config
    @battery_energy_grid = battery_energy_grid
  end

  attr_reader :day, :day_records, :config, :battery_energy_grid

  def call
    group_by_period(split_all).map { |elem| point(elem) }
  end

  private

  PERIOD = 5.minutes
  private_constant :PERIOD

  # Length of a single record. Taken from the reader that produces them rather
  # than restated here: how a period is grouped, how long a record integrates
  # for and what counts as a missing one all have to follow it.
  RECORD_DURATION = Flux::Reader::RECORD_DURATION
  private_constant :RECORD_DURATION

  # The battery ledger carries over from record to record, so the records must
  # be processed in chronological order.
  #
  # A gap in the records breaks the chain: nothing is known about what the
  # battery did in between, so the ledger starts empty again. This is the same
  # rule that Flux::LastState applies when seeding a day - it just has to hold
  # within a day as well, not only across the boundary.
  #
  # A record that lost one of the sensors the ledger is built from breaks it
  # just as much, and is the more likely of the two: the record is still there
  # as long as any other sensor reports.
  def split_all
    balance = battery_energy_grid

    # The seed describes the state at the day boundary, so that is where the
    # chain begins - a day whose data starts hours later is behind a gap too.
    #
    # Which boundary that is comes from the day being processed, not from the
    # records: a record is stamped at the end of the minute it covers, so a day
    # holding nothing but the one stamped at the next midnight - data returning
    # at 23:59 after a day-long outage - would take that record for its own
    # beginning and pay the seed out across the whole outage.
    previous_time = day.in_time_zone(config.time_zone)

    day_records.map do |record|
      time = record['time']
      balance = 0 if gap?(previous_time, time) || blind?(record)
      previous_time = time

      split_power(record, balance).tap do |splitted|
        balance = splitted[:battery_energy_grid] || balance
      end
    end
  end

  # What counts is a missing record, not the time between two of them: records
  # are dropped only once every sensor has been silent past MAX_AGE, so a
  # single one missing already is the data gap the ledger must not cross.
  # Measuring the distance against MAX_AGE instead would add that window a
  # second time, and the ledger would survive twice the silence.
  def gap?(previous_time, time)
    time - previous_time > RECORD_DURATION
  end

  # Sensors the ledger is computed from: what went into the battery from the
  # grid, and what came back out of it. The import and the house power because
  # without them there is no split at all and the charge cannot be told apart
  # from PV; the two battery sensors because they are the deposit and the
  # withdrawal themselves.
  LEDGER_SENSORS = %i[
    grid_import_power
    house_power
    battery_charging_power
    battery_discharging_power
  ].freeze
  private_constant :LEDGER_SENSORS

  # A record missing one of them is as blind as no record at all: a value is
  # dropped only once its sensor has been silent past MAX_AGE, so the battery
  # may well have been filled or emptied in the meantime without any of it being
  # seen. Carrying the balance across that would hand out energy that is no
  # longer there, or label PV as grid.
  #
  # Without both battery sensors nothing is tracked anyway, and the balance this
  # keeps at zero is one nobody reads.
  def blind?(record)
    LEDGER_SENSORS.any? { |sensor| power_value(record, sensor).nil? }
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

  # A record is timestamped at the end of the minute it covers, so shifting it
  # back by one record length gives the period it belongs to.
  def group_by_period(splitted)
    splitted
      .group_by { |item| (item[:time].to_i - RECORD_DURATION) / PERIOD }
      .map do |interval, items|
        keys = items.flat_map(&:keys).uniq - [:time]
        minutes = covered(items)

        keys
          .to_h { |key| [key, aggregate(items, key, minutes)] }
          .merge(time: period_center(interval))
          .compact
      end
  end

  # The timestamp of a period is derived from the period itself, not from the
  # records it holds: minutes can be missing, and a group whose records end
  # early would otherwise be stamped too far back - at midnight even into the
  # previous day, where it would corrupt that day's battery ledger.
  def period_center(interval)
    config.time_zone.at((interval * PERIOD.to_i) + (PERIOD.to_i / 2))
  end

  def aggregate(items, key, minutes)
    return last(items, key) if STATE_FIELDS.include?(key)

    avg(items, key, minutes)
  end

  # Minutes of the period the split covers. A minute without grid data yields
  # no shares at all, and there is nothing to average over it - which is what
  # makes both shapes of a gap agree: a minute missing from the period and a
  # minute present but unsplittable give the same result.
  #
  # The ledger balance does not count. It is carried through a minute that
  # could not be split as well, and would make one look covered.
  def covered(items)
    items.count do |item|
      item.any? do |key, value|
        !value.nil? && key != :time && !STATE_FIELDS.include?(key)
      end
    end
  end

  # Averaged over the minutes the split covers, not over the minutes this one
  # field reported. The shares of the consumers add up to the grid import and
  # the discharge share, and only a denominator they all share keeps that true:
  # a sensor gone for part of the period drew nothing from the grid while it
  # was gone, and the split gave its share to the others.
  def avg(items, key, minutes)
    values = items.filter_map { |item| item[key] }
    return if values.empty?

    values.sum.fdiv(minutes).round
  end

  def last(items, key)
    items.reverse.filter_map { |item| item[key] }.first
  end

  def power_value(record, sensor_name, default = nil)
    identifier = config.identifier(sensor_name)

    record[identifier] || default
  end

  # The sensors house power is broken out into, in the order they are listed.
  # Which ones those are follows from the config alone, so the list is drawn up
  # once rather than searched per record - of the twenty-two candidates a
  # typical config names two.
  def excluded_sensors
    @excluded_sensors ||=
      [:heatpump_power, :wallbox_power, *config.custom_sensors] &
        config.exclude_from_house_power
  end

  # House power is mandatory, so a record without it is a gap rather than a
  # sensor that does not exist. Reading it as zero would claim the house drew
  # nothing from the grid and shrink the key the split is proportional to.
  def adjusted_house_power(record)
    result = power_value(record, :house_power)
    return if result.nil?

    excluded_sensors.each { |sensor| result -= power_value(record, sensor, 0) }

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
