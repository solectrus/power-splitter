require 'splitter/base'

module Splitter
  class Mixed < Base
    def call
      house_power_grid = 0
      wallbox_power_grid = 0
      heatpump_power_grid = 0

      remaining = grid_import_power

      # When the battery is charging while importing from the grid,
      # this power should not be attributed to consumer usage
      remaining -= battery_charging_power

      # Wallbox power is prioritized over other consumers
      if remaining.positive? && wallbox_power.positive?
        wallbox_power_grid = [wallbox_power, remaining].min
        remaining -= wallbox_power_grid
      end

      # Now we have to split the remaining power between the house and the heatpump
      house_and_heatpump_power = house_power + heatpump_power
      if remaining.positive? && house_and_heatpump_power.positive?
        house_power_ratio = house_power.fdiv(house_and_heatpump_power)
        heatpump_power_ratio = heatpump_power.fdiv(house_and_heatpump_power)

        house_power_grid = [remaining * house_power_ratio, house_power].min
        heatpump_power_grid = [
          remaining * heatpump_power_ratio,
          heatpump_power,
        ].min
      end

      { house_power_grid:, wallbox_power_grid:, heatpump_power_grid: }
    end
  end
end
