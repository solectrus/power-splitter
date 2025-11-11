require 'loop'
require 'config'

describe Loop do
  subject(:loop) { described_class.new(config:, max_count: 1) }

  let(:config) { Config.new(ENV.to_h, logger:) }
  let(:logger) { MemoryLogger.new }

  it 'can be initialized' do
    expect(loop).to be_a(described_class)
  end

  describe '#start', vcr: 'loop-start' do
    subject(:start) { loop.start }

    it 'starts the loop' do
      expect { start }.to(change { config.logger.info_messages.size })
    end
  end

  describe '#restart', vcr: 'loop-restart' do
    subject(:start) { loop.restart }

    context "when there's a thread" do
      before { loop.__send__ :start_thread }

      it 'restarts the loop' do
        expect { start }.to(change { config.logger.info_messages.size })
      end
    end

    context "when there's no thread" do
      it 'does nothing' do
        expect { start }.not_to(change { config.logger.info_messages.size })
      end
    end
  end

  describe '#process_historical_data' do
    let(:influx_pull) { instance_double(InfluxPull) }
    let(:postgres_summaries) { instance_double(PostgresSummaries, reset: nil) }

    before do
      allow(Date).to receive(:current).and_return(Date.new(2025, 10, 14))
      allow(InfluxPull).to receive(:new).and_return(influx_pull)
      allow(influx_pull).to receive_messages(
        last_splitter_date: Date.new(2025, 10, 10),
        day_records: [],
      )
      allow(RedisCache).to receive(:new).and_return(
        instance_double(RedisCache, flush: nil),
      )
      allow(PostgresSummaries).to receive(:new).and_return(postgres_summaries)
    end

    it 'resets PostgreSQL summaries from the first processed day' do
      loop.__send__(:process_historical_data)

      expect(postgres_summaries).to have_received(:reset).with(
        since: Date.new(2025, 10, 10),
      )
    end
  end
end
