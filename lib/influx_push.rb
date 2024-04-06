require 'flux/writer'
require 'forwardable'

class InfluxPush
  extend Forwardable
  def_delegators :config, :logger

  def initialize(config:)
    @config = config
    @flux_writer = Flux::Writer.new(config:)
  end

  attr_reader :config, :flux_writer

  def call(records, retries: nil, retry_delay: 5)
    retry_count = 0
    begin
      config.logger.debug "Pushing #{records.size} records to InfluxDB"
      flux_writer.push(records)
    rescue StandardError => e
      logger.error "Error while pushing to InfluxDB: #{e.message}"
      retry_count += 1

      raise e if retries && retry_count > retries

      sleep(retry_delay)
      retry
    end
  end
end
