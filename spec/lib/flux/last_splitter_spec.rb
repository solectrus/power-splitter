require 'flux/last_splitter'

describe Flux::LastSplitter do
  subject(:last_splitter) { described_class.new(config:) }

  describe '#time' do
    context 'when there are no records', vcr: 'last_splitter-without-records' do
      it 'returns nil' do
        expect(last_splitter.time).to be_nil
      end
    end

    context 'when there are records', vcr: 'last_splitter-with-records' do
      let(:first_time) { Time.new('2022-01-01 12:00:00 +01:00') }
      let(:second_time) { Time.new('2022-05-17 13:00:00 +02:00') }

      before do
        records = [
          {
            time: first_time,
            name: config.influx_measurement,
            fields: {
              'heatpump_power_grid' => 42,
              'house_power_grid' => 42,
              'wallbox_power_grid' => 42,
            },
          },
          {
            time: second_time,
            name: config.influx_measurement,
            fields: {
              'heatpump_power_grid' => 43,
              'house_power_grid' => 43,
              'wallbox_power_grid' => 43,
            },
          },
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
        expect(last_splitter.time).to eq(second_time)
      end
    end
  end
end
