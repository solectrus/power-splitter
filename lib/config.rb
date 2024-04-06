require 'uri'
require 'null_logger'

class Config
  attr_accessor :influx_schema,
                :influx_host,
                :influx_port,
                :influx_token,
                :influx_org,
                :influx_bucket

  def initialize(env, logger: NullLogger.new)
    @logger = logger

    # InfluxDB credentials
    @influx_schema = env.fetch('INFLUX_SCHEMA', 'http')
    @influx_host = env.fetch('INFLUX_HOST')
    @influx_port = env.fetch('INFLUX_PORT', '8086')
    @influx_token = env.fetch('INFLUX_TOKEN')
    @influx_org = env.fetch('INFLUX_ORG')
    @influx_bucket = env.fetch('INFLUX_BUCKET')

    validate_url!(influx_url)
  end

  def influx_url
    "#{influx_schema}://#{influx_host}:#{influx_port}"
  end

  attr_reader :logger

  private

  def validate_url!(url)
    URI.parse(url)
  end
end
