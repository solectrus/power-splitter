require 'influxdb-client'
require 'influx_push'

class Loop
  extend Forwardable
  def_delegators :config, :logger

  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def start
  rescue SystemExit, Interrupt
    logger.warn 'Exiting...'
  end

  def influx_push
    @influx_push ||= InfluxPush.new(config:)
  end
end
