require 'flux/writer'
require 'flux/deleter'

class InfluxPush
  def initialize(config:)
    @config = config
    @flux_writer = Flux::Writer.new(config:)
    @flux_deleter = Flux::Deleter.new(config:)
  end

  attr_reader :config, :flux_writer, :flux_deleter

  def push(records, retries: nil, retry_delay: 5)
    retry_count = 0
    begin
      config.logger.info "  Pushing #{records.size} records to InfluxDB"

      flux_writer.push(records)
    rescue StandardError => e
      config.logger.error "  Error while pushing to InfluxDB: #{e.message}"
      retry_count += 1

      raise e if retries && retry_count > retries

      sleep(retry_delay)
      retry
    end
  end

  def delete_all
    flux_deleter.delete_all
  end

  def delete_measurement(measurement)
    flux_deleter.delete_measurement(measurement)
  end
end
