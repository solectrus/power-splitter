require 'uri'
require 'active_support'
require 'active_support/core_ext'
require 'null_logger'

class Config # rubocop:disable Metrics/ClassLength
  attr_accessor :influx_schema,
                :influx_host,
                :influx_port,
                :influx_token,
                :influx_org,
                :influx_bucket,
                :interval,
                :redis_url,
                :time_zone

  def initialize(env, logger: NullLogger.new)
    @logger = logger

    # InfluxDB credentials
    @influx_schema = env.fetch('INFLUX_SCHEMA', 'http')
    @influx_host = env.fetch('INFLUX_HOST')
    @influx_port = env.fetch('INFLUX_PORT', '8086')
    @influx_token = env.fetch('INFLUX_TOKEN')
    @influx_org = env.fetch('INFLUX_ORG')
    @influx_bucket = env.fetch('INFLUX_BUCKET')
    @interval = [env.fetch('POWER_SPLITTER_INTERVAL', '3600').to_i, 300].max
    validate_url!(influx_url)
    logger.info "Accessing InfluxDB at #{influx_url}, bucket #{influx_bucket}"

    @time_zone = env.fetch('TZ', 'Europe/Berlin')
    @redis_url = env.fetch('REDIS_URL', nil)

    init_sensors(env)
    validate_sensors!
  end

  def influx_url
    "#{influx_schema}://#{influx_host}:#{influx_port}"
  end

  attr_reader :logger

  def influx_measurement
    'power_splitter'
  end

  def measurement(sensor_name)
    @measurement ||= {}
    @measurement[sensor_name] ||= splitted_sensor_name(sensor_name)&.first
  end

  def field(sensor_name)
    @field ||= {}
    @field[sensor_name] ||= splitted_sensor_name(sensor_name)&.last
  end

  def identifier(sensor_name)
    sensor_method = sensor_name.downcase
    return unless respond_to?(sensor_method)

    public_send(sensor_method)
  end

  def exists?(sensor_name)
    case sensor_name
    when *SENSOR_NAMES
      measurement(sensor_name).present? && field(sensor_name).present?
    else
      raise ArgumentError,
            "Unknown or invalid sensor name: #{sensor_name.inspect}"
    end
  end

  def sensor_names
    @sensor_names ||= SENSOR_NAMES.filter { |sensor_name| exists?(sensor_name) }
  end

  private

  def validate_url!(url)
    URI.parse(url)
  end

  def init_sensors(env)
    logger.info 'Sensor initialization started'
    SENSOR_NAMES.each do |sensor_name|
      var_sensor = var_for(sensor_name)
      value = env.fetch(var_sensor, nil).presence
      next unless value

      validate!(sensor_name, value)
      define_sensor(sensor_name, value)
    end

    define_exclude_from_house_power(
      env.fetch('INFLUX_EXCLUDE_FROM_HOUSE_POWER', nil).presence,
    )
    logger.info 'Sensor initialization completed'
  end

  def validate_sensors!
    unless exists?(:wallbox_power) || exists?(:heatpump_power)
      raise Error,
            'At least one of INFLUX_SENSOR_WALLBOX_POWER or INFLUX_SENSOR_HEATPUMP_POWER must be set.'
    end

    unless exists?(:grid_import_power)
      raise Error, 'INFLUX_SENSOR_GRID_IMPORT_POWER must be set.'
    end

    unless exists?(:house_power)
      raise Error, 'INFLUX_SENSOR_HOUSE_POWER must be set.'
    end

    true
  end

  class Error < RuntimeError
  end

  SENSOR_NAMES = %i[
    grid_import_power
    house_power
    heatpump_power
    wallbox_power
  ].freeze
  public_constant :SENSOR_NAMES

  def define_sensor(sensor_name, value)
    logger.info "  - Sensor '#{sensor_name}' #{value ? "mapped to '#{value}'" : 'ignored'}"

    define(sensor_name, value)
  end

  def define_exclude_from_house_power(value)
    unless value
      logger.info "  - Sensor 'house_power' remains unchanged"
      define(:exclude_from_house_power, [])
      return
    end

    sensors_to_exclude =
      value.split(',').map { |sensor| sensor.strip.downcase.to_sym }

    if sensors_to_exclude.any? { |sensor| SENSOR_NAMES.exclude?(sensor) }
      raise Error,
            "Invalid sensor name in INFLUX_EXCLUDE_FROM_HOUSE_POWER: #{value}"
    end

    logger.info "  - Sensor 'house_power' excluded '#{sensors_to_exclude.join(', ')}'"
    define(:exclude_from_house_power, sensors_to_exclude)
  end

  def var_for(sensor_name)
    "INFLUX_SENSOR_#{sensor_name.upcase}"
  end

  def define(sensor_name, value)
    self.class.attr_accessor(sensor_name)
    instance_variable_set(:"@#{sensor_name}", value)
  end

  # Format is "measurement:field"
  SENSOR_REGEX = /\A\S+:\S+\z/
  private_constant :SENSOR_REGEX

  def validate!(sensor_name, value)
    return if value.nil?
    return if value.match?(SENSOR_REGEX)

    raise Error,
          "Sensor '#{sensor_name}' must be in format 'measurement:field'. Got this instead: '#{value}'"
  end

  def splitted_sensor_name(sensor_name)
    identifier(sensor_name)&.split(':')
  end
end
