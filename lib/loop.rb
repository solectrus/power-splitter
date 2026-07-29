require 'influx_push'
require 'influx_pull'
require 'processor'
require 'redis_cache'
require 'postgres_summaries'

class Loop
  def initialize(config:, max_count: nil, max_wait: 12)
    @config = config
    @max_count = max_count
    @max_wait = max_wait
  end

  attr_reader :config, :thread, :restarting, :max_count, :max_wait

  def start
    exit(1) unless influx_ready?(max_wait)

    Signal.trap('USR1') { restart }

    loop do
      start_thread

      # There are two reasons we get here:
      # 1. The thread finished accidentally, so we should stop by breaking the loop.
      # 2. We received a USR1 signal and should restart.
      break unless restarting

      # Restart requested, so delete all data and loop again.
      delete_all
      @restarting = false
    end
  rescue SystemExit, Interrupt
    config.logger.warn 'Exiting...'
    raise
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
      process_pending_days(last_time)

      # Process the current day
      last_time = Time.current
      process_day(Date.current)

      count += 1
      break if max_count && count >= max_count

      config.logger.info "  Sleeping for #{config.interval} seconds...\n\n"
      sleep(config.interval)
    end
  end

  # Complete every day that ended while we were busy. After a long stall more
  # than one day can be pending, and none of them may be skipped: a day passed
  # over here is never written at all, and nothing comes back for it later. The
  # range is empty while we are still on the same day.
  def process_pending_days(last_time)
    return unless last_time

    (last_time.to_date..Date.yesterday).each { process_day(it) }
  end

  def process_historical_data
    day = influx_pull.last_splitter_date || config.installation_date || influx_pull.first_sensor_date
    return unless day
    return if day >= Date.current

    config.logger.info "--- Processing historical data since #{day}"

    (day..Date.current).each { process_day(it) }

    RedisCache.new(config:).flush
    PostgresSummaries.new(config:).reset(since: day)

    config.logger.info '--- Processing historical data successfully finished'
  end

  # Days must be processed in chronological order: the battery ledger of a day
  # continues where the previous day left off.
  def process_day(day)
    config.logger.info "\n#{Time.current} - Processing day #{day}"

    day_records = influx_pull.day_records(day.beginning_of_day)
    return if day_records.empty?

    splitted_powers =
      Processor.new(
        day_records:,
        config:,
        battery_energy_grid: battery_energy_grid_for(day),
      ).call
    influx_push.push(splitted_powers)
  end

  # Seed for the battery ledger, read back from InfluxDB so that recalculating
  # a day always starts from the same value.
  #
  # Without a recent balance the ledger starts empty. That happens at the very
  # beginning and after a gap in the data - and after a gap an old balance
  # would be a guess, not a measurement.
  def battery_energy_grid_for(day)
    return 0 unless config.battery_tracking?

    balance = influx_pull.battery_energy_grid_before(day.beginning_of_day)
    return balance if balance

    config.logger.info '  No recent battery ledger balance, starting empty'
    0
  end

  def delete_all
    config.logger.info "\n--- Deleting all records from InfluxDB measurement '#{config.influx_measurement}'"
    influx_push.delete_measurement(config.influx_measurement)
    config.logger.info "  Ok, deleted successfully\n\n"
  end

  def influx_ready?(max_wait)
    count = 0
    until (ready = influx_push.flux_writer.ready?) || (max_wait && count >= max_wait)
      count += 1
      config.logger.info "Wait until InfluxDB is ready ... (#{count}/#{max_wait || '∞'})"
      sleep 5
    end
    return true if ready

    config.logger.error "InfluxDB not ready after #{count * 5} seconds - aborting."
    false
  end

  def influx_push
    @influx_push ||= InfluxPush.new(config:)
  end

  def influx_pull
    @influx_pull ||= InfluxPull.new(config:)
  end
end
