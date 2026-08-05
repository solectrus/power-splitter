require 'outdated_records'
require 'config'

describe OutdatedRecords do
  subject(:outdated_records) { described_class.new(config:) }

  # Battery tracking needs a discharging sensor, so it is on by default here
  let(:config) { Config.new(ENV.to_h.merge(extra_env)) }
  let(:extra_env) do
    { 'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER' => 'SENEC:bat_power_minus' }
  end
  let(:last_splitter_date) { Date.new(2025, 10, 10) }
  let(:ledger_written) { true }

  before do
    influx_pull = instance_double(InfluxPull)
    allow(influx_pull).to receive_messages(
      last_splitter_date:,
      battery_ledger_written?: ledger_written,
    )
    allow(InfluxPull).to receive(:new).and_return(influx_pull)
  end

  describe '#exist?' do
    context 'when the records predate the battery ledger' do
      let(:ledger_written) { false }

      it 'returns true' do
        expect(outdated_records.exist?).to be(true)
      end
    end

    context 'when the records carry the battery ledger' do
      it 'returns false' do
        expect(outdated_records.exist?).to be(false)
      end
    end

    context 'when nothing was written yet' do
      let(:last_splitter_date) { nil }
      let(:ledger_written) { false }

      it 'returns false' do
        expect(outdated_records.exist?).to be(false)
      end
    end

    # Without both battery sensors the field is never written, so its absence
    # says nothing about the version - and acting on it would wipe the
    # measurement on every start.
    context 'without battery tracking' do
      let(:extra_env) { {} }
      let(:ledger_written) { false }

      it 'returns false' do
        expect(outdated_records.exist?).to be(false)
      end
    end
  end
end
