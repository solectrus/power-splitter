require 'loop'
require 'config'

describe Loop do
  subject(:loop) { described_class.new(config:, max_count: 1) }

  let(:config) { Config.new(ENV.to_h.merge(extra_env), logger:) }
  let(:extra_env) { {} }
  let(:logger) { MemoryLogger.new }

  before do
    flux_writer = instance_double(Flux::Writer, ready?: true)
    influx_push = instance_double(InfluxPush, flux_writer:)
    allow(InfluxPush).to receive(:new).and_return(influx_push)
  end

  it 'can be initialized' do
    expect(loop).to be_a(described_class)
  end

  describe '#start', vcr: 'loop-start' do
    subject(:start) { loop.start }

    # Starting the loop works through every day since the installation, and
    # against an empty InfluxDB that date comes from the environment - the one
    # of the real system, years back. Pinned to yesterday here, because a fixed
    # date would put one more day between itself and the present with every day
    # that passes, and a recording made a year from now would query a year's
    # worth of days.
    let(:extra_env) { { 'INSTALLATION_DATE' => Date.yesterday.to_s } }

    it 'starts the loop' do
      expect { start }.to(change { config.logger.info_messages.size })
    end
  end

  describe '#restart', vcr: 'loop-restart' do
    subject(:start) { loop.restart }

    # Same as above: the loop runs for real here too.
    let(:extra_env) { { 'INSTALLATION_DATE' => Date.yesterday.to_s } }

    context "when there's a thread" do
      before { loop.__send__ :start_thread }

      it 'restarts the loop' do
        expect { start }.to(change { config.logger.info_messages.size })
      end
    end

    context "when there's no thread" do
      it 'does nothing' do
        expect { start }.not_to(change { config.logger.info_messages.size })
      end
    end
  end

  describe '#process_historical_data' do
    let(:influx_pull) { instance_double(InfluxPull) }
    let(:postgres_summaries) { instance_double(PostgresSummaries, reset: nil) }

    before do
      allow(Date).to receive(:current).and_return(Date.new(2025, 10, 14))
      allow(InfluxPull).to receive(:new).and_return(influx_pull)
      allow(influx_pull).to receive_messages(
        last_splitter_date: Date.new(2025, 10, 10),
        day_records: [],
      )
      allow(RedisCache).to receive(:new).and_return(
        instance_double(RedisCache, flush: nil),
      )
      allow(PostgresSummaries).to receive(:new).and_return(postgres_summaries)
    end

    it 'resets PostgreSQL summaries from the first processed day' do
      loop.__send__(:process_historical_data)

      expect(postgres_summaries).to have_received(:reset).with(
        since: Date.new(2025, 10, 10),
      )
    end
  end

  describe '#process_pending_days' do
    subject(:process) { loop.__send__(:process_pending_days, last_time) }

    let(:influx_pull) { instance_double(InfluxPull, day_records: []) }

    before do
      allow(Date).to receive(:current).and_return(Date.new(2025, 10, 14))
      allow(InfluxPull).to receive(:new).and_return(influx_pull)
    end

    context 'when never run before' do
      let(:last_time) { nil }

      it 'processes nothing' do
        process

        expect(influx_pull).not_to have_received(:day_records)
      end
    end

    context 'when still on the same day' do
      let(:last_time) { Time.new(2025, 10, 14, 6, 0, 0) }

      it 'processes nothing' do
        process

        expect(influx_pull).not_to have_received(:day_records)
      end
    end

    context 'when the day just rolled over' do
      let(:last_time) { Time.new(2025, 10, 13, 23, 55, 0) }

      it 'completes yesterday' do
        process

        expect(influx_pull).to have_received(:day_records).with(
          Date.new(2025, 10, 13).beginning_of_day,
        ).once
      end
    end

    # A stalled iteration must not leave a hole: a skipped day is never
    # written at all, and nothing comes back to fill it in later.
    context 'when multiple days were missed' do
      let(:last_time) { Time.new(2025, 10, 11, 8, 0, 0) }

      it 'completes them in chronological order' do
        process

        expect(influx_pull).to have_received(:day_records).with(
          Date.new(2025, 10, 11).beginning_of_day,
        ).ordered
        expect(influx_pull).to have_received(:day_records).with(
          Date.new(2025, 10, 12).beginning_of_day,
        ).ordered
        expect(influx_pull).to have_received(:day_records).with(
          Date.new(2025, 10, 13).beginning_of_day,
        ).ordered
      end
    end
  end

  describe '#discard_outdated_records' do
    subject(:discard) { loop.__send__(:discard_outdated_records) }

    let(:outdated_records) { instance_double(OutdatedRecords, exist?: true) }
    let(:influx_push) { instance_double(InfluxPush, delete_measurement: nil) }

    before do
      allow(OutdatedRecords).to receive(:new).and_return(outdated_records)
      allow(InfluxPush).to receive(:new).and_return(influx_push)
    end

    context 'when the records are outdated' do
      it 'deletes the measurement' do
        discard

        expect(influx_push).to have_received(:delete_measurement).with(
          config.influx_measurement,
        )
      end
    end

    context 'when the records are up to date' do
      let(:outdated_records) { instance_double(OutdatedRecords, exist?: false) }

      it 'keeps them' do
        discard

        expect(influx_push).not_to have_received(:delete_measurement)
      end
    end
  end

  describe '#battery_energy_grid_for' do
    subject(:seed) { loop.__send__(:battery_energy_grid_for, day) }

    # Battery tracking needs a discharging sensor, so it is on by default here
    let(:extra_env) do
      { 'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER' => 'SENEC:bat_power_minus' }
    end
    let(:state) { nil }

    def day
      Date.new(2025, 10, 14)
    end

    before do
      influx_pull = instance_double(InfluxPull)
      allow(influx_pull).to receive(:battery_energy_grid_before).and_return(
        state,
      )
      allow(InfluxPull).to receive(:new).and_return(influx_pull)
    end

    context 'without battery tracking' do
      let(:extra_env) { {} }

      it 'starts empty' do
        expect(seed).to eq(0)
      end
    end

    context 'when nothing was written yet' do
      it 'starts empty' do
        expect(seed).to eq(0)
      end
    end

    context 'when the previous day left a balance' do
      let(:state) { 123.4 }

      it 'continues where the previous day left off' do
        expect(seed).to eq(123.4)
      end
    end

    # Anything outside the lookback window reads as nil, so a gap in the data
    # and a fresh start are the same case here.
    context 'when the balance is out of reach' do
      it 'says so' do
        seed

        expect(logger.info_messages.join).to include('starting empty')
      end
    end
  end
end
