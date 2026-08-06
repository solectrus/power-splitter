require 'influx_pull'
require 'config'

describe InfluxPull do
  subject(:influx_pull) { described_class.new(config:) }

  let(:config) { Config.new(ENV) }
  let(:time) { Time.new('2022-01-01 12:00:00 +01:00') }

  def point(fields)
    InfluxDB2::Point.new(
      name: config.influx_measurement,
      time: time.to_i,
      fields:,
    )
  end

  after { flux_cleanup }

  # Both readers answer with a date, and with nothing at all while the bucket
  # is still empty - which is where FirstDay and the loop start from.
  describe '#first_sensor_date' do
    context 'when no sensor ever reported',
            vcr: 'influx_pull-first_sensor_empty' do
      it 'is nil' do
        expect(influx_pull.first_sensor_date).to be_nil
      end
    end

    context 'when a sensor reported',
            vcr: {
              cassette_name: 'influx_pull-first_sensor',
              match_requests_on: %i[method uri flux_query],
            } do
      before do
        flux_write(
          InfluxDB2::Point.new(
            name: 'SENEC',
            time: time.to_i,
            fields: {
              'grid_power_plus' => 42,
            },
          ),
        )
      end

      it 'is the day it first reported' do
        expect(influx_pull.first_sensor_date).to eq(time.to_date)
      end
    end
  end

  describe '#last_splitter_date' do
    context 'when nothing was split yet',
            vcr: 'influx_pull-last_splitter_empty' do
      it 'is nil' do
        expect(influx_pull.last_splitter_date).to be_nil
      end
    end

    context 'when a day was split',
            vcr: {
              cassette_name: 'influx_pull-last_splitter',
              match_requests_on: %i[method uri flux_query],
            } do
      before { flux_write(point('house_power_grid' => 42)) }

      it 'is the day it last wrote' do
        expect(influx_pull.last_splitter_date).to eq(time.to_date)
      end
    end
  end

  describe '#battery_energy_grid_before',
           vcr: {
             cassette_name: 'influx_pull-battery_energy_grid',
             match_requests_on: %i[method uri flux_query],
           } do
    before do
      flux_write(point('house_power_grid' => 42, 'battery_energy_grid' => 100.5))
    end

    it 'reads the balance the ledger had before that moment' do
      expect(influx_pull.battery_energy_grid_before(time + 1.hour)).to eq(100.5)
    end
  end

  describe '#battery_ledger_written?',
           vcr: {
             cassette_name: 'influx_pull-battery_ledger_written',
             match_requests_on: %i[method uri flux_query],
           } do
    before do
      flux_write(point('house_power_grid' => 42, 'battery_energy_grid' => 0.0))
    end

    it 'sees the ledger in what was written' do
      expect(influx_pull.battery_ledger_written?).to be(true)
    end
  end
end
