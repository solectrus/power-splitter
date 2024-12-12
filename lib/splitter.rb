class Splitter
  def initialize(config, **kwargs)
    @config = config

    @grid_import_power = kwargs[:grid_import_power]
    @battery_charging_power = kwargs[:battery_charging_power]
    @house_power = kwargs[:house_power]
    @wallbox_power = kwargs[:wallbox_power]
    @heatpump_power = kwargs[:heatpump_power]
    @custom_power = kwargs[:custom_power] || []
  end

  attr_reader :config,
              :grid_import_power,
              :battery_charging_power,
              :house_power,
              :wallbox_power,
              :heatpump_power,
              :custom_power

  def call # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    remaining = grid_import_power

    # When the battery is charging while importing from the grid,
    # this power should not be attributed to consumer usage
    remaining -= battery_charging_power if battery_charging_power

    # Wallbox power is prioritized over other consumers
    if remaining&.positive? && wallbox_power&.positive?
      wallbox_power_grid = [wallbox_power, remaining].min
      remaining -= wallbox_power_grid
    else
      wallbox_power_grid = wallbox_power ? 0 : nil
    end

    # Now we have to split the remaining power between the other consumers
    result = {
      wallbox_power_grid:,
      house_power_grid: grid_power(remaining, house_power, other_total),
      heatpump_power_grid: grid_power(remaining, heatpump_power, other_total),
    }

    # Add custom power fields dynamically
    custom_power.each_with_index do |cp, index|
      cp_grid = grid_power(remaining, cp, other_total)

      result[format('custom_power_%02d_grid', index + 1).to_sym] = cp_grid
    end

    result
  end

  private

  def other_total
    @other_total ||=
      (house_power || 0) + (heatpump_power || 0) + custom_power_total
  end

  def custom_power_total
    # Only use custom sensors which are separate (= excluded from house power)
    config.exclude_from_house_power.sum do |sensor|
      if (match = sensor.to_s.match(/\Acustom_power_(\d{2})\z/))
        index = match[1].to_i
        custom_power[index - 1] || 0
      else
        0
      end
    end
  end

  def grid_power(remaining, power, total)
    return unless power
    return 0 unless total.positive? && remaining.positive?

    ratio = power.fdiv(total)
    [remaining * ratio, power].min
  end
end
