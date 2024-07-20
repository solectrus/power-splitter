require 'splitter/base'

module Splitter
  class Proportional < Base
    def call
      house_power_grid = 0
      wallbox_power_grid = 0
      heatpump_power_grid = 0

      if grid_import_power.positive? && total.positive?
        house_power_ratio = house_power.fdiv(total)
        wallbox_power_ratio = wallbox_power.fdiv(total)
        heatpump_power_ratio = heatpump_power.fdiv(total)

        house_power_grid = [
          grid_import_power * house_power_ratio,
          house_power,
        ].min

        wallbox_power_grid = [
          grid_import_power * wallbox_power_ratio,
          wallbox_power,
        ].min

        heatpump_power_grid = [
          grid_import_power * heatpump_power_ratio,
          heatpump_power,
        ].min
      end

      { house_power_grid:, wallbox_power_grid:, heatpump_power_grid: }
    end
  end
end
