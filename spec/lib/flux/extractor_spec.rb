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
        { time:,
          name: 'SENEC',
          fields: {
            'grid_power_plus' => 42,
            'house_power' => 42,
            'wallbox_charge_power' => 42,
          }, },

        { time:,
          name: 'Consumer',
          fields: {
            'power' => 42,
          }, },
      ]

      points = records.map do |record|
        InfluxDB2::Point.new(
          name: record[:name],
          time:,
          fields: record[:fields],
        )
      end

      write_api.write(data: points)
    end

    def write_api
      influx_client.create_write_api
    end

    def influx_client
      @influx_client ||=
        InfluxDB2::Client.new(
          config.influx_url,
          config.influx_token,
          use_ssl: config.influx_schema == 'https',
          precision: InfluxDB2::WritePrecision::SECOND,
          bucket: config.influx_bucket,
          org: config.influx_org,
          read_timeout: 30,
        )
    end

    it 'returns transformed data' do
      records = extractor.records(day)

      expect(records).to be_an(Array)
        .and all(be_a(Hash))
        .and all(include('time',
                         'grid_power_plus', 'house_power', 'wallbox_charge_power', 'power',))

      expect(records.length).to eq(288) # 24 hours * 12 records per hour (5m intervals)
    end
  end
end
