require 'influx_push'
require 'flux/last_splitter'
require 'config'

describe InfluxPush do
  subject(:influx_push) { described_class.new(config:) }

  let(:config) { Config.new(ENV, logger: MemoryLogger.new) }

  it 'initializes with a config' do
    expect(influx_push.config).to eq(config)
  end

  it 'can push records to InfluxDB', vcr: 'influx_success' do
    time = Time.current.to_i
    records = [
      {
        time:,
        name: config.influx_measurement,
        fields: {
          'heatpump_power_grid' => 42,
          'house_power_grid' => 42,
          'wallbox_power_grid' => 42,
        },
      },
      {
        time:,
        name: config.influx_measurement,
        fields: {
          'heatpump_power_grid' => 43,
          'house_power_grid' => 43,
          'wallbox_power_grid' => 43,
        },
      },
    ]

    result = influx_push.push(records)
    expect(result).to be_truthy
  end

  it 'can handle error' do
    fake_flux = instance_double(Flux::Writer)
    allow(fake_flux).to receive(:push).and_raise(StandardError)
    allow(Flux::Writer).to receive(:new).and_return(fake_flux)

    time = Time.current
    records = [{ time:, key: 'value' }]

    expect do
      influx_push.push(records, retries: 1, retry_delay: 0.1)
    end.to raise_error(StandardError)

    expect(config.logger.error_messages).to include(
      /Error while pushing to InfluxDB: StandardError/,
    )
  end

  describe '#delete_measurement',
           vcr: {
             cassette_name: 'influx_push-delete',
             match_requests_on: %i[method uri flux_query],
           } do
    before do
      flux_write(
        InfluxDB2::Point.new(
          name: config.influx_measurement,
          time: Time.new('2022-01-01 12:00:00 +01:00').to_i,
          fields: {
            'house_power_grid' => 42,
          },
        ),
      )
    end

    after { flux_cleanup }

    it 'removes what was written' do
      expect do
        influx_push.delete_measurement(config.influx_measurement)
      end.to change { Flux::LastSplitter.new(config:).time }.to(nil)
    end
  end
end
