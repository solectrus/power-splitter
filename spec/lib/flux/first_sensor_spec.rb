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

      after { flux_delete_all }

      it 'returns time' do
        expect(first_sensor.time).to eq(first_time)
      end
    end
  end
end
