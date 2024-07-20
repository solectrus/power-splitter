require 'loop'
require 'config'

describe Loop do
  subject(:loop) { described_class.new(config:) }

  let(:config) { Config.new(ENV.to_h, logger:) }
  let(:logger) { MemoryLogger.new }

  it 'can be initialized' do
    expect(loop).to be_a(described_class)
  end
end
