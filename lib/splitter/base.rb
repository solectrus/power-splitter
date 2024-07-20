module Splitter
  class Base
    def initialize(
      grid_import_power:,
      house_power:,
      wallbox_power:,
      heatpump_power:
    )
      @grid_import_power = grid_import_power
      @house_power = house_power
      @wallbox_power = wallbox_power
      @heatpump_power = heatpump_power
    end

    attr_reader :grid_import_power,
                :house_power,
                :wallbox_power,
                :heatpump_power

    def call
      raise NotImplementedError
    end

    private

    def total
      @total ||= house_power + wallbox_power + heatpump_power
    end
  end
end
