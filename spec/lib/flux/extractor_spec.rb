require 'flux/extractor'
require 'config'

describe Flux::Extractor do
  subject(:extractor) { described_class.new(config:) }

  let(:config) { Config.new(ENV) }
  let(:day) { Date.yesterday }

  describe '#records', vcr: 'extractor' do
    let(:time) { day.to_time.change(hour: 9, minute: 42).to_i }

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
        { time:, name: 'Consumer', fields: { 'power' => 42 } },
      ]

      points =
        records.map do |record|
          InfluxDB2::Point.new(
            name: record[:name],
            time:,
            fields: record[:fields],
          )
        end

      flux_write(points)
    end

    after { flux_delete_all }

    it 'returns transformed data' do
      records = extractor.records(day)

      expect(records).to be_an(Array).and all(be_a(Hash)).and all(
                    include(
                      'time',
                      'grid_power_plus',
                      'house_power',
                      'wallbox_charge_power',
                      'power',
                    ),
                  )

      expect(records.length).to eq(1440) # 24 hours * 60 records per hour (1m intervals)
    end
  end
end
