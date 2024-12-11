require 'influx_push'
require 'influx_pull'
require 'processor'
require 'redis_cache'

class Loop
  def initialize(config:, max_count: nil)
    @config = config
    @max_count = max_count
  end

  attr_reader :config, :thread, :restarting, :max_count

  def start
    Signal.trap('USR1') { restart }

    loop do
      start_thread

      # There are two reasons we get here:
      # 1. The thread finished accidentally, so we should stop by breaking the loop.
      # 2. We received a USR1 signal and should restart.
      break unless restarting

      # Restart requsted, so delete all data and loop again.
      delete_all
      @restarting = false
    end
  rescue SystemExit, Interrupt
    config.logger.warn 'Exiting...'
  end

  def restart
    unless thread
      config.logger.warn "\n--- No thread to restart..."
      return
    end

    config.logger.info "\n--- Restarting..."
    @restarting = true

    # Terminate the thread
    thread.exit

    # Wait for the thread to finish
    timeout = Time.current + 5
    sleep(1) while thread.alive? && Time.current < timeout

    if thread.alive?
      config.logger.warn 'Thread did not finish in time.'
      thread.kill
      config.logger.warn 'Thread killed.'
    else
      config.logger.info 'Thread exited cleanly.'
    end
  end

  private

  def start_thread
    @thread =
      Thread.new do # rubocop:disable ThreadSafety/NewThread
        process_historical_data
        process_current_data
      end
    thread.join
  end

  def process_current_data
    config.logger.info "\nStarting endless loop for processing current data..."

    count = 0
    last_time = nil
    loop do
      # Ensure that the last minutes of yesterday are processed
      if last_time && last_time.to_date < Date.current
        process_day(Date.yesterday)
      end

      # Process the current day
      last_time = Time.current
      process_day(Date.current)

      count += 1
      break if max_count && count >= max_count

      config.logger.info "  Sleeping for #{config.interval} seconds...\n\n"
      sleep(config.interval)
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

    RedisCache.new(config:).flush

    config.logger.info '--- Processing historical data successfully finished'
  end

  def process_day(day)
    config.logger.info "\n#{Time.current} - Processing day #{day}"

    day_records = influx_pull.day_records(day.beginning_of_day)
    return if day_records.empty?

    splitted_powers = Processor.new(day_records:, config:).call
    influx_push.push(splitted_powers)
  end

  def delete_all
    config.logger.info "\n--- Deleting all records from InfluxDB measurement '#{config.influx_measurement}'"
    influx_push.delete_measurement(config.influx_measurement)
    config.logger.info "  Ok, deleted successfully\n\n"
  end

  def influx_push
    @influx_push ||= InfluxPush.new(config:)
  end

  def influx_pull
    @influx_pull ||= InfluxPull.new(config:)
  end
end
