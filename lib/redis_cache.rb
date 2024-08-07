require 'redis'

class RedisCache
  def initialize(config:)
    @config = config
  end
  attr_reader :config

  def flush
    unless redis
      config.logger.warn 'REDIS_URL not set, skipping Redis cache flush'
      return
    end

    result = redis.flushall
    if result == 'OK'
      config.logger.info 'Redis cache flushed'
    else
      config.logger.error "Flushing Redis cache failed: #{result}"
    end
  rescue StandardError => e
    config.logger.error "Flushing Redis cache failed: #{e.message}"
  end

  def redis
    return unless config.redis_url

    @redis ||= Redis.new(url: config.redis_url)
  end
end
