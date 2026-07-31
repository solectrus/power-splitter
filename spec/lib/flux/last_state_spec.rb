require 'flux/last_state'

describe Flux::LastState do
  subject(:last_state) { described_class.new(config:) }

  let(:first_time) { Time.new('2022-01-01 12:00:00 +01:00') }
  let(:second_time) { Time.new('2022-01-01 13:00:00 +01:00') }

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
