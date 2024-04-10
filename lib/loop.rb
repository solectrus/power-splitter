require 'influxdb-client'
require 'influx_push'
require 'influx_pull'
require 'calculator'

class Loop
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def start # rubocop:disable Metrics/AbcSize
    config.logger.info "Deleting all records from InfluxDB measurement '#{config.influx_measurement}'"
    influx_push.delete_all

    config.logger.info 'Starting loop'
    day = config.installation_date

    while day <= Time.now
      config.logger.info "\nProcessing day #{day}"

      day_records = influx_pull.day_records(day.beginning_of_day)
      splitted_powers = Calculator.new(day_records:, config:).call

      influx_push.push(splitted_powers)

      day += 1.day
    end
  rescue SystemExit, Interrupt
    config.logger.warn 'Exiting...'
  end

  def influx_push
    @influx_push ||= InfluxPush.new(config:)
  end

  def influx_pull
    @influx_pull ||= InfluxPull.new(config:)
  end
end
