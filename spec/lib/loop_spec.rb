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
end
