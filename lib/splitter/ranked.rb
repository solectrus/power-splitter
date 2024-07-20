require 'splitter/base'

module Splitter
  class Ranked < Base
    def call
      house_power_grid = 0
      wallbox_power_grid = 0
      heatpump_power_grid = 0

      remaining = grid_import_power

      if remaining.positive? && wallbox_power.positive?
        wallbox_power_grid = [wallbox_power, grid_import_power].min
        remaining -= wallbox_power_grid
      end

      if remaining.positive? && heatpump_power.positive?
        heatpump_power_grid = [heatpump_power, remaining].min
        remaining -= heatpump_power_grid
      end

      if remaining.positive? && house_power.positive?
        house_power_grid = [house_power, remaining].min
      end

      { house_power_grid:, wallbox_power_grid:, heatpump_power_grid: }
    end
  end
end
