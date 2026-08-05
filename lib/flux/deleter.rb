require_relative 'base'

module Flux
  class Deleter < Flux::Base
    # A deletion is always a time range - InfluxDB requires both ends of it -
    # and we never mean anything but everything the predicate matches. So the
    # range is set wider than any record can be, and nothing about it depends
    # on the clock.
    #
    # Wider includes the future, which is not an academic case: a period is
    # written under the timestamp of its center, so the one being measured
    # right now lands ahead of the present. Ending the range there would leave
    # that record behind, and a single one left over is enough to defeat a
    # rebuild - it dates the data to today, which is where processing would
    # have to resume anyway.
    BEGINNING = Time.utc(1970)
    END_OF_TIME = Time.utc(2100)
    private_constant :BEGINNING, :END_OF_TIME

    def delete_measurement(measurement)
      delete(measurement:)
    end

    def delete_all
      delete
    end

    private

    def delete(measurement: nil)
      delete_api.delete(
        BEGINNING,
        END_OF_TIME,
        predicate: measurement ? "_measurement=\"#{measurement}\"" : nil,
      )
    end
  end
end
