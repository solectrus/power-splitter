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
    # influx_push.delete_measurement(config.influx_measurement)
    # config.logger.info "  Ok, deleted sucessfully\n\n"

    process_historical_data
    process_current_data
  rescue SystemExit, Interrupt
    config.logger.warn 'Exiting...'
  end

  private

  def process_current_data
    config.logger.info "\nStarting endless loop for processing current data..."

    last_time = nil
    loop do
      # Ensure that the last minutes of yesterday are processed
      if last_time && last_time.to_date < Date.current
        process_day(Date.yesterday)
      end

      # Process the current day
      last_time = Time.current
      process_day(Date.current)

      config.logger.info "  Sleeping for #{config.influx_interval} seconds...\n\n"
      sleep(config.influx_interval)
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
    return if day_records.empty?

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
