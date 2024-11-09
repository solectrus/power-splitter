require_relative 'base'

module Flux
  class Deleter < Flux::Base
    def delete_measurement(measurement)
      delete(measurement:)
    end

    def delete_all
      delete
    end

    private

    def delete(measurement: nil)
      delete_api.delete(
        Time.at(0),
        Time.current,
        predicate: measurement ? "_measurement=\"#{measurement}\"" : nil,
      )
    end
  end
end
