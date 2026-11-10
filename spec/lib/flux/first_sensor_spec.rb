require 'flux/first_sensor'

describe Flux::FirstSensor do
  subject(:first_sensor) { described_class.new(config:) }

  describe '#time' do
    context 'when there are no records', vcr: 'first_sensor-without-records' do
      it 'returns nil' do
        expect(first_sensor.time).to be_nil
      end
    end

    context 'when there are records', vcr: 'first_sensor-with-records' do
      let(:first_time) { Time.new('2022-01-01 12:00:00 +01:00') }
      let(:second_time) { Time.new('2022-05-17 13:00:00 +02:00') }

      before do
        records = [
          {
            time: first_time,
            name: 'SENEC',
            fields: {
              'grid_power_plus' => 42,
              'house_power' => 42,
              'wallbox_charge_power' => 42,
            },
          },
          { time: second_time, name: 'Consumer', fields: { 'power' => 42 } },
        ]

        points =
          records.map do |record|
            InfluxDB2::Point.new(
              name: record[:name],
              time: record[:time].to_i,
              fields: record[:fields],
            )
          end

        flux_write(points)
      end

      after { flux_cleanup }

      it 'returns time' do
        expect(first_sensor.time).to eq(first_time)
      end
    end

    context 'when searching from a given time',
            vcr: {
              cassette_name: 'first_sensor-since',
              match_requests_on: %i[method uri flux_query],
            } do
      let(:stray_time) { Time.new('1970-01-01 01:00:01 +01:00') }
      let(:real_time) { Time.new('2022-01-01 12:00:00 +01:00') }

      before do
        flux_write(
          [stray_time, real_time].map do |time|
            InfluxDB2::Point.new(
              name: 'SENEC',
              time: time.to_i,
              fields: { 'house_power' => 42 },
            )
          end,
        )
      end

      after { flux_cleanup }

      it 'returns the first time at or after it' do
        expect(first_sensor.time(since: Time.new('1970-01-02 00:00:00 +01:00'))).to eq(
          real_time,
        )
      end
    end
  end
end
