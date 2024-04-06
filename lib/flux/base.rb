require 'influxdb-client'

module Flux
  class Base
    def initialize(config:)
      @config = config
    end

    attr_reader :config

    def influx_client
      @influx_client ||=
        InfluxDB2::Client.new(
          config.influx_url,
          config.influx_token,
          use_ssl: config.influx_schema == 'https',
          precision: InfluxDB2::WritePrecision::SECOND,
          bucket: config.influx_bucket,
          org: config.influx_org,
          read_timeout: 30,
        )
    end

    def write_api
      @write_api ||= influx_client.create_write_api
    end

    def read_api
      @read_api ||= influx_client.create_query_api
    end
  end
end
