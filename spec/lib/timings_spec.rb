require 'timings'

describe Timings do
  subject(:timings) { described_class.new }

  describe '#measure' do
    it 'returns what the block returned' do
      expect(timings.measure(:read) { 42 }).to eq(42)
    end

    it 'books a phase that raised' do
      expect { timings.measure(:read) { raise ArgumentError } }.to raise_error(
        ArgumentError,
      )

      expect(timings.to_s).to include('read')
    end
  end

  describe '#to_s' do
    it 'reports nothing but the total when no phase ran' do
      expect(timings.to_s).to eq('total 0.0s')
    end

    it 'reports the phases in the order they were measured' do
      timings.measure(:read) { nil }
      timings.measure(:calc) { nil }

      expect(timings.to_s).to match(
        /\Aread \d+\.\d+s, calc \d+\.\d+s, total \d+\.\d+s\z/,
      )
    end

    it 'adds the phases up' do
      allow(Process).to receive(:clock_gettime).and_return(0, 1.5, 1.5, 4.0)

      timings.measure(:read) { nil }
      timings.measure(:calc) { nil }

      expect(timings.to_s).to eq('read 1.5s, calc 2.5s, total 4.0s')
    end
  end
end
