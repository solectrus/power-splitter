require 'flux/reader'

describe Flux::Reader do
  subject(:reader) { described_class.new(config:) }

  let(:config) do
    instance_double(Config, time_zone: ActiveSupport::TimeZone['Europe/Berlin'])
  end

  describe '#parse_influx_time' do
    subject(:result) { reader.parse_influx_time(utc_timestamp) }

    context 'when 22:30 UTC in summer' do
      let(:utc_timestamp) { '2025-08-05T22:30:00Z' }

      it 'returns NEXT day in Europe/Berlin' do
        # UTC 22:30 + 2h (CEST) = 00:30 => next day
        expect(result.to_date.to_s).to eq('2025-08-06')
      end
    end

    context 'when 22:30 UTC in winter' do
      let(:utc_timestamp) { '2025-01-15T22:30:00Z' }

      it 'returns SAME day in Europe/Berlin' do
        # UTC 22:30 + 1h (CET) = 23:30 => same day
        expect(result.to_date.to_s).to eq('2025-01-15')
      end
    end
  end
end
