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

  def call
    remaining = grid_power_for_consumers

    # Prioritize wallbox power over all other consumers
    if remaining&.positive? && wallbox_power&.positive?
      wallbox_power_grid = [wallbox_power, remaining].min
      remaining -= wallbox_power_grid
    else
      wallbox_power_grid = wallbox_power ? 0 : nil
    end

    # Distribute the remaining grid power among the other consumers
    {
      wallbox_power_grid:,
      house_power_grid: grid_power(remaining, house_power),
      heatpump_power_grid: grid_power(remaining, heatpump_power),
    }.tap do |result|
      # Add custom power fields dynamically, based on the configuration
      custom_power.each_with_index do |cp, index|
        key = format('custom_power_%02d_grid', index + 1).to_sym
        result[key] = grid_power(remaining, cp)
      end
    end
  end

  private

  # Calculate the grid power used by all consumers
  # (battery charging is NOT considered a consumer)
  def grid_power_for_consumers
    return unless grid_import_power

    grid_import_power - (battery_charging_power || 0)
  end

  # Sum up all consumers except wallbox power
  def other_total
    @other_total ||=
      (house_power || 0) + (heatpump_power || 0) + custom_power_total
  end

  # Sum up only the custom sensors explicitly excluded from house power
  def custom_power_total
    config.exclude_from_house_power.sum do |sensor|
      index = sensor.to_s[/\Acustom_power_(\d{2})\z/, 1]&.to_i
      index ? (custom_power[index - 1] || 0) : 0
    end
  end

  # Allocate grid power proportionally to the consumer's share of the total power
  def grid_power(remaining, power)
    return unless power && other_total && remaining
    return 0 unless other_total.positive?

    ratio = power.fdiv(other_total)
    [remaining * ratio, power].min
  end
end
