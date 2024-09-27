require 'redis_cache'

describe RedisCache do
  subject(:redis_cache) { described_class.new(config:) }

  let(:config) { Config.new(ENV.to_h, logger:) }
  let(:logger) { MemoryLogger.new }

  describe '#flush' do
    subject(:flush) { redis_cache.flush }

    context 'when Redis is available' do
      it 'writes info message into log' do
        flush

        expect(logger.info_messages).to include('Redis cache flushed')
      end
    end

    context 'when Redis is not available' do
      before do
        allow(config).to receive(:redis_url).and_return(
          'redis://localhost:1234',
        )
      end

      it 'writes error message into log' do
        flush

        expect(logger.error_messages).to include(
          /Flushing Redis cache failed: Connection refused/,
        )
      end
    end

    context 'when Redis cannot flush' do
      before do
        allow(Redis).to receive(:new).and_return(
          instance_double(Redis, flushall: 'ERROR'),
        )
      end

      it 'writes error message into log' do
        flush

        expect(logger.error_messages).to include(
          'Flushing Redis cache failed: ERROR',
        )
      end
    end

    context 'when REDIS_URL missing' do
      before { allow(config).to receive(:redis_url).and_return(nil) }

      it 'writes warn message into log' do
        flush

        expect(logger.warn_messages).to include(
          'REDIS_URL not set, skipping Redis cache flush',
        )
      end
    end
  end
end
