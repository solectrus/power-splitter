require 'flux/first'
require 'flux/day'
require 'forwardable'

class InfluxPull
  extend Forwardable
  def_delegators :config, :logger

  def initialize(config:)
    @config = config
    @flux_reader = Flux::Reader.new(config:)
  end

  attr_reader :flux_reader, :config

  def first_time
    Flux::First.new(config:).time
  end

  def day_records(day)
    Flux::Day.new(config:).records(day)
  end
end
