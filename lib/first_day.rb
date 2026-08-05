require 'influx_pull'

# The day processing begins with as long as the splitter has not written
# anything yet.
#
#   FirstDay.new(config:).date # => Fri, 27 Nov 2020
#
# That is where the sensor data begins, but never before the installation date:
# what a sensor reported before the PV system existed cannot be split.
#
# Nil when there is no sensor data at all, and that case is the point of asking
# InfluxDB rather than trusting the installation date alone: a day without
# records writes nothing, so it leaves no mark to resume from, and every start
# would walk the same years again.
class FirstDay
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def date
    first_sensor_date = influx_pull.first_sensor_date
    return unless first_sensor_date

    [first_sensor_date, config.installation_date].compact.max
  end

  private

  def influx_pull
    @influx_pull ||= InfluxPull.new(config:)
  end
end
