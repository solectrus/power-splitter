require 'influx_push'
require 'config'

describe InfluxPush do
  subject(:influx_push) { described_class.new(config:) }

  let(:config) do
    Config.new(ENV, logger: MemoryLogger.new)
  end

  it 'initializes with a config' do
    expect(influx_push.config).to eq(config)
  end

  it 'can push records to InfluxDB', vcr: 'influx_success' do
    time = Time.now
    records = [{ time:,
                 house_power_from_grid: 100, house_power_from_pv: 200,
                 wallbox_power_from_grid: 300, wallbox_power_from_pv: 600,
                 heatpump_power_from_grid: 500, heatpump_power_from_pv: 1000, }]

    influx_push.push(records)
  end

  it 'can handle error' do
    fake_flux = instance_double(Flux::Writer)
    allow(fake_flux).to receive(:push).and_raise(StandardError)
    allow(Flux::Writer).to receive(:new).and_return(fake_flux)

    time = Time.now
    records = [{ time:, key: 'value' }]

    expect do
      influx_push.push(records, retries: 1, retry_delay: 0.1)
    end.to raise_error(StandardError)

    expect(config.logger.error_messages).to include(
      /Error while pushing to InfluxDB: StandardError/,
    )
  end
end
