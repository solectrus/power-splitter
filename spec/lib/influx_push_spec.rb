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
    fake_flux = instance_double(Flux::Writer)
    allow(fake_flux).to receive(:push)
    allow(Flux::Writer).to receive(:new).and_return(fake_flux)

    time = Time.now
    records = [{ time:, key: 'value' }]

    influx_push.call(records)
  end

  it 'can handle error' do
    fake_flux = instance_double(Flux::Writer)
    allow(fake_flux).to receive(:push).and_raise(StandardError)
    allow(Flux::Writer).to receive(:new).and_return(fake_flux)

    time = Time.now
    records = [{ time:, key: 'value' }]

    expect do
      influx_push.call(records, retries: 1, retry_delay: 0.1)
    end.to raise_error(StandardError)

    expect(config.logger.error_messages).to include(
      'Error while pushing to InfluxDB: StandardError',
    )
    sleep(1)
  end
end
