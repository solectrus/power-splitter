require 'first_day'
require 'config'

describe FirstDay do
  subject(:first_day) { described_class.new(config:) }

  let(:config) { Config.new(ENV.to_h.merge(extra_env)) }
  let(:extra_env) { { 'INSTALLATION_DATE' => '2025-10-01' } }
  let(:first_sensor_date) { Date.new(2025, 10, 5) }

  before do
    influx_pull = instance_double(InfluxPull, first_sensor_date:)
    allow(InfluxPull).to receive(:new).and_return(influx_pull)
  end

  describe '#date' do
    it 'returns the day the sensor data begins' do
      expect(first_day.date).to eq(Date.new(2025, 10, 5))
    end

    context 'when the sensor data predates the installation' do
      let(:first_sensor_date) { Date.new(2025, 9, 20) }

      it 'returns the installation date' do
        expect(first_day.date).to eq(Date.new(2025, 10, 1))
      end
    end

    context 'without an installation date' do
      let(:extra_env) { { 'INSTALLATION_DATE' => '' } }

      it 'returns the day the sensor data begins' do
        expect(first_day.date).to eq(Date.new(2025, 10, 5))
      end
    end

    # Nothing to process, and nothing that would ever be written - so saying so
    # is what keeps the next start from walking the same days again.
    context 'without any sensor data' do
      let(:first_sensor_date) { nil }

      it 'returns nil' do
        expect(first_day.date).to be_nil
      end
    end
  end
end
