require 'influx_push'
require 'influx_pull'
require 'calculator'

class Loop
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def start
    # config.logger.info "--- Deleting all records from InfluxDB measurement '#{config.influx_measurement}'"
    # influx_push.delete_all
    # config.logger.info "  Ok, deleted sucessfully\n\n"

    process_historical_data
    process_current_data
  rescue SystemExit, Interrupt
    config.logger.warn 'Exiting...'
  end

  private

  def process_current_data
    config.logger.info "\nStarting endless loop for processing current data..."

    loop do
      process_day(Date.current)

      config.logger.info "  Sleeping for 5 minutes...\n\n"
      sleep(5.minutes)
    end
  end

  def process_historical_data
    day = influx_pull.last_splitter_date || influx_pull.first_sensor_date
    return unless day
    return if day >= Date.current

    config.logger.info "--- Processing historical data since #{day}"

    while day <= Date.current
      process_day(day)
      day += 1.day
    end

    config.logger.info '--- Processing historical data successfully finished'
  end

  def process_day(day)
    config.logger.info "\n#{Time.current} - Processing day #{day}"

    day_records = influx_pull.day_records(day.beginning_of_day)
    splitted_powers = Calculator.new(day_records:, config:).call

    influx_push.push(splitted_powers)
  end

  def influx_push
    @influx_push ||= InfluxPush.new(config:)
  end

  def influx_pull
    @influx_pull ||= InfluxPull.new(config:)
  end
end
