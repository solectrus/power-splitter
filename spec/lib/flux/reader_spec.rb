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

    # The hour the clocks go forward, where a zone carries two offsets in one
    # day. Read as UTC and moved into the zone afterwards, which is the only
    # order that has one answer.
    context 'when the clocks go forward' do
      let(:utc_timestamp) { '2025-03-30T01:00:00Z' }

      it 'lands after the jump, with the summer offset' do
        expect(result.strftime('%H:%M')).to eq('03:00')
        expect(result.utc_offset).to eq(2.hours)
      end
    end

    context 'when the clocks go back' do
      let(:utc_timestamp) { '2025-10-26T01:00:00Z' }

      it 'lands after the jump, with the winter offset' do
        expect(result.strftime('%H:%M')).to eq('02:00')
        expect(result.utc_offset).to eq(1.hour)
      end
    end

    # Not a timestamp at all now says so, where the lenient parser it replaced
    # would have answered nil and left the row without a time.
    context 'when the column holds something else' do
      let(:utc_timestamp) { 'the day before yesterday' }

      it 'says so' do
        expect { result }.to raise_error(ArgumentError)
      end
    end
  end
end
