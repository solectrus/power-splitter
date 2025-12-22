require_relative 'base'

module Flux
  class Writer < Flux::Base
    def push(records)
      write_api.write(data: records)
    end

    def ready?
      influx_client.ping.status == 'ok'
    end
  end
end
