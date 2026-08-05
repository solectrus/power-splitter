require 'flux/first_sensor'
require 'flux/last_splitter'
require 'flux/last_state'
require 'flux/extractor'

class InfluxPull
  def initialize(config:)
    @config = config
    @flux_reader = Flux::Reader.new(config:)
  end

  attr_reader :flux_reader, :config

  def first_sensor_date
    Flux::FirstSensor.new(config:).time&.to_date
  end

  def last_splitter_date
    Flux::LastSplitter.new(config:).time&.to_date
  end

  def day_records(day)
    Flux::Extractor.new(config:).records(day)
  end

  def battery_energy_grid_before(time)
    Flux::LastState.new(config:).battery_energy_grid(before: time)
  end

  def battery_ledger_written?
    Flux::LastState.new(config:).written?
  end
end
