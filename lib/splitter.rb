require 'allocator'
require 'battery_ledger'

# Splits the power of each consumer into the part that originates from the grid
# and the part that does not (which is PV).
#
# This happens in two stages:
#
#   1. The power currently imported from the grid is distributed among the
#      consumers, including the battery while it is charging.
#   2. The power currently taken out of the battery is distributed among the
#      remaining consumption. How much of it originates from the grid is then
#      answered by the ledger, which knows how much grid energy was put into
#      the battery earlier.
#
# The ledger is threaded through as a plain balance so that a day can be
# recalculated from a known starting point at any time.
class Splitter
  def initialize(config, **kwargs)
    @config = config

    @grid_import_power = kwargs[:grid_import_power]
    @battery_charging_power = kwargs[:battery_charging_power]
    @battery_discharging_power = kwargs[:battery_discharging_power]
    @house_power = kwargs[:house_power]
    @wallbox_power = kwargs[:wallbox_power]
    @heatpump_power = kwargs[:heatpump_power]
    @custom_power = kwargs[:custom_power] || []
    @ledger = BatteryLedger.new(kwargs[:battery_energy_grid])
    @duration = kwargs.fetch(:duration, 1.minute)
  end

  attr_reader :config,
              :grid_import_power,
              :battery_charging_power,
              :battery_discharging_power,
              :house_power,
              :wallbox_power,
              :heatpump_power,
              :custom_power,
              :ledger,
              :duration

  def call
    consumer_powers
      .keys
      .to_h { |key| [:"#{key}_grid", grid_share(key)] }
      .merge(battery_grid_share, ledger_balance)
  end

  private

  # Grid share of a consumer: what it took directly from the grid, plus - if
  # attribution is enabled - the grid-sourced part of what it took from the
  # battery.
  def grid_share(key)
    direct = grid_allocator.call[key]
    return direct unless config.battery_grid_attribution?

    battery = battery_allocator.call[key]
    return direct if direct.nil? || battery.nil?

    direct + (battery * battery_grid_ratio)
  end

  # The grid electricity the battery handed to the consumers, as a power of
  # its own - a second source besides the import, by which the consumers' grid
  # shares now exceed it. Only reported when the attribution actually happened,
  # because otherwise nothing was added to those shares.
  def battery_grid_share
    return {} unless config.battery_grid_attribution?

    { battery_discharging_power_grid: to_power(withdrawn_energy) }
  end

  # The only state that has to survive a record: what a later day is seeded
  # with. Unlike the powers around it, it is carried over rather than averaged.
  def ledger_balance
    return {} unless config.battery_tracking?

    { battery_energy_grid: updated_ledger.balance }
  end

  # Stage 1: the power imported from the grid right now
  def grid_allocator
    @grid_allocator ||=
      Allocator.new(
        pool: grid_import_power,
        wallbox: wallbox_power,
        powers: consumer_powers.except(:wallbox_power),
        counted:,
      )
  end

  # Stage 2: the power taken out of the battery right now, over whatever is
  # left after stage 1. The battery is not a recipient of its own discharge.
  def battery_allocator
    @battery_allocator ||=
      Allocator.new(
        pool: battery_discharging_power,
        wallbox: remaining(:wallbox_power),
        powers:
          consumer_powers
            .except(:wallbox_power, :battery_charging_power)
            .to_h { |key, _power| [key, remaining(key)] },
        counted:,
      )
  end

  # Power of a consumer that is not yet covered by stage 1 - and unknown as
  # long as stage 1 is. Without the grid import there is no telling what is
  # left, so nothing is distributed and the ledger stays where it is, just as
  # nothing is booked into it.
  def remaining(key)
    power = consumer_powers[key]
    direct = grid_allocator.call[key]
    return if power.nil? || direct.nil?

    [power - direct, 0].max
  end

  def consumer_powers
    @consumer_powers ||= {
      house_power:,
      wallbox_power:,
      heatpump_power:,
      battery_charging_power:,
      **custom_powers,
    }
  end

  def custom_powers
    custom_power.each_with_index.to_h do |power, index|
      [format('custom_power_%02d', index + 1).to_sym, power]
    end
  end

  # Consumers that draw from a pool, as opposed to custom sensors that are
  # merely a breakdown of house power.
  def counted
    @counted ||=
      consumer_powers.keys.reject do |key|
        key.to_s.start_with?('custom_power_') &&
          !config.exclude_from_house_power.include?(key)
      end
  end

  # Grid-sourced part of what the battery handed to the consumers, limited by
  # what the ledger holds
  def withdrawn_energy
    @withdrawn_energy ||= ledger.offered(allocated_energy)
  end

  def allocated_energy
    @allocated_energy ||= to_energy(battery_allocator.allocated)
  end

  def battery_grid_ratio
    return 0.0 unless allocated_energy.positive?

    withdrawn_energy / allocated_energy
  end

  # Pay out before booking the deposit: energy charged in this very minute is
  # not available for discharging in the same minute.
  def updated_ledger
    @updated_ledger ||=
      ledger.withdraw(withdrawn_energy).deposit(
        to_energy(grid_allocator.call[:battery_charging_power]),
      )
  end

  def to_energy(power)
    (power || 0) * duration.in_hours
  end

  def to_power(energy)
    energy / duration.in_hours
  end
end
