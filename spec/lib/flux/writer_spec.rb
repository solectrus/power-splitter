require 'flux/writer'
require 'config'

describe Flux::Writer do
  subject(:writer) { described_class.new(config:) }

  let(:config) { Config.new(ENV) }

  describe '#ready?' do
    context 'when InfluxDB answers', vcr: 'writer-ready' do
      it 'is true' do
        expect(writer.ready?).to be(true)
      end
    end

    # The client turns an unreachable server into a status rather than an
    # exception, so an InfluxDB that is not up yet arrives here as a plain
    # false - which is what the startup wait is built on.
    context 'when InfluxDB is not up yet' do
      before { stub_request(:get, %r{/ping}).to_timeout }

      it 'is false' do
        expect(writer.ready?).to be(false)
      end
    end
  end
end
