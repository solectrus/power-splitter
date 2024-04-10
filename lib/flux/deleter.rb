require_relative 'base'

module Flux
  class Deleter < Flux::Base
    def delete_all
      delete_api.delete(
        Time.at(0),
        Time.now,
        predicate: "_measurement=\"#{config.influx_measurement}\"",
      )
    end
  end
end
