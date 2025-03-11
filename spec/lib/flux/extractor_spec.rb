require 'flux/extractor'
require 'config'

describe Flux::Extractor do
  subject(:extractor) { described_class.new(config:) }

  let(:config) { Config.new(ENV) }

  describe '#records', vcr: 'extractor' do
    subject(:day_records) { extractor.records(day) }

    let(:time) { day.to_time.change(hour: 9, min: 42) }

    before do
      records = [
        {
          time:,
          name: 'SENEC',
          fields: {
            'grid_power_plus' => 42,
            'house_power' => 42,
            'wallbox_charge_power' => 42,
          },
        },
        { time:, name: 'Heatpump', fields: { 'power' => 42 } },
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

    context 'when day is in the past' do
      let(:day) { Date.yesterday }

      it 'returns transformed data' do
        expect(day_records).to be_an(Array).and all(be_a(Hash)).and all(
                      include(
                        'time',
                        'SENEC:grid_power_plus',
                        'SENEC:house_power',
                        'SENEC:wallbox_charge_power',
                        'Heatpump:power',
                      ),
                    )

        expect(day_records.length).to eq(1440) # 24 hours * 60 records per hour (1m intervals)
      end
    end

    context 'when day is today' do
      let(:day) { Date.new(2024, 8, 28) }

      before { travel_to(time) }

      it 'returns transformed data' do
        expect(day_records).to be_an(Array).and all(be_a(Hash)).and all(
                      include(
                        'time',
                        'SENEC:grid_power_plus',
                        'SENEC:house_power',
                        'SENEC:wallbox_charge_power',
                        'Heatpump:power',
                      ),
                    )

        expect(day_records.length).to eq(1440) # 24 hours * 60 records per hour (1m intervals)
      end
    end
  end
end
