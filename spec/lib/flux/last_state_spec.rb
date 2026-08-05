require 'flux/last_state'

describe Flux::LastState do
  subject(:last_state) { described_class.new(config:) }

  let(:first_time) { Time.new('2022-01-01 12:00:00 +01:00') }
  let(:second_time) { Time.new('2022-01-01 13:00:00 +01:00') }

  def point(fields)
    InfluxDB2::Point.new(
      name: config.influx_measurement,
      time: first_time.to_i,
      fields:,
    )
  end

  describe '#written?' do
    context 'when the measurement is empty', vcr: 'last_state-written-empty' do
      it 'returns false' do
        expect(last_state.written?).to be(false)
      end
    end

    context 'when the records predate the ledger',
            vcr: {
              cassette_name: 'last_state-written-without-ledger',
              match_requests_on: %i[method uri flux_query],
            } do
      before { flux_write(point('house_power_grid' => 42)) }

      after { flux_delete_all }

      it 'returns false' do
        expect(last_state.written?).to be(false)
      end
    end

    # Older than the lookback window on purpose: this is about the whole
    # history, not about a balance that can still be carried forward.
    context 'when the ledger was written',
            vcr: {
              cassette_name: 'last_state-written-with-ledger',
              match_requests_on: %i[method uri flux_query],
            } do
      before do
        flux_write(point('house_power_grid' => 42, 'battery_energy_grid' => 0.0))
      end

      after { flux_delete_all }

      it 'returns true' do
        expect(last_state.written?).to be(true)
      end
    end
  end

  describe '#battery_energy_grid' do
    context 'when there are no records', vcr: 'last_state-without-records' do
      it 'returns nil' do
        expect(last_state.battery_energy_grid(before: second_time)).to be_nil
      end
    end

    context 'when there are records',
            vcr: {
              cassette_name: 'last_state-with-records',
              match_requests_on: %i[method uri flux_query],
            } do
      before do
        points =
          [[first_time, 100.5], [second_time, 200.5]].map do |time, balance|
            InfluxDB2::Point.new(
              name: config.influx_measurement,
              time: time.to_i,
              fields: {
                'house_power_grid' => 42,
                'battery_energy_grid' => balance,
              },
            )
          end

        flux_write(points)
      end

      after { flux_delete_all }

      it 'returns the last balance before the given time' do
        expect(last_state.battery_energy_grid(before: second_time)).to eq(100.5)

        expect(
          last_state.battery_energy_grid(before: second_time + 1.hour),
        ).to eq(200.5)
      end

      it 'ignores balances older than the lookback window' do
        expect(
          last_state.battery_energy_grid(
            before: second_time + described_class::MAX_AGE + 1.minute,
          ),
        ).to be_nil
      end
    end
  end
end
