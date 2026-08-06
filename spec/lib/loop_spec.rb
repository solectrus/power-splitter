require 'loop'
require 'flux/last_splitter'
require 'config'

# What Loop waits on is Kernel#sleep and a thread of its own, neither of which
# can be handed in - so covering the waiting and the restart means stubbing
# them on the object under test.
# rubocop:disable RSpec/SubjectStub
describe Loop do
  subject(:loop) { described_class.new(config:, max_count: 1) }

  let(:config) { Config.new(ENV.to_h.merge(extra_env), logger:) }
  let(:extra_env) { {} }
  let(:logger) { MemoryLogger.new }

  it 'can be initialized' do
    expect(loop).to be_a(described_class)
  end

  describe '#start' do
    subject(:start) { loop.start }

    # Recorded against an empty InfluxDB, where there is no day to work
    # through: only the machinery around it runs here. Which day processing
    # would begin with is covered by FirstDay.
    context 'with nothing to work through', vcr: 'loop-start' do
      it 'starts the loop' do
        expect { start }.to(change { config.logger.info_messages.size })
      end
    end

    # Carrying the ledger, so that the outdated-records check leaves it alone
    # and the deletion seen here is the restart's own.
    context 'when a restart was requested',
            vcr: {
              cassette_name: 'loop-start_restart',
              match_requests_on: %i[method uri flux_query],
            } do
      before do
        flux_write(
          InfluxDB2::Point.new(
            name: config.influx_measurement,
            time: Time.new('2022-01-01 12:00:00 +01:00').to_i,
            fields: {
              'house_power_grid' => 42,
              'battery_energy_grid' => 0.0,
            },
          ),
        )

        # A real restart flips the flag from the signal handler, which is
        # nothing a spec can time: the first pass ends with it set, the second
        # one leaves the loop.
        passes = [true, false]
        allow(loop).to receive(:start_thread) do
          loop.instance_variable_set(:@restarting, passes.shift)
        end
      end

      after { flux_cleanup }

      it 'throws away what it calculated' do
        expect { start }.to change { Flux::LastSplitter.new(config:).time }.to(
          nil,
        )
      end
    end

    # Nothing can be read or written without it, so there is no point in
    # entering the loop at all.
    context 'when InfluxDB never comes up' do
      before do
        stub_request(:get, %r{/ping}).to_timeout
        allow(loop).to receive(:sleep)
      end

      it 'gives up instead of starting' do
        expect { start }.to raise_error(SystemExit)
      end
    end

    context 'when interrupted', vcr: 'loop-start_interrupt' do
      before { allow(loop).to receive(:start_thread).and_raise(Interrupt) }

      it 'passes the interrupt on' do
        expect { start }.to raise_error(Interrupt)
        expect(logger.warn_messages).to include('Exiting...')
      end
    end
  end

  describe '#restart', vcr: 'loop-restart' do
    subject(:start) { loop.restart }

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

    # A thread stuck in a read that ignores #exit must not hold the restart
    # forever - after the grace period it is killed.
    context "when the thread doesn't finish in time" do
      let(:thread) { instance_double(Thread, exit: nil, alive?: true, kill: nil) }

      before do
        allow(loop).to receive(:thread).and_return(thread)
        allow(loop).to receive(:sleep) { travel 2.seconds }
      end

      it 'kills it' do
        start

        expect(thread).to have_received(:kill)
        expect(logger.warn_messages).to include('Thread killed.')
      end
    end
  end

  describe '#process_current_data',
           vcr: {
             cassette_name: 'loop-process_current_data',
             match_requests_on: %i[method uri flux_query],
           } do
    subject(:loop) { described_class.new(config:, max_count: 2) }

    before do
      travel_to Time.new('2024-06-12 06:00:00 +02:00')
      allow(loop).to receive(:sleep)
    end

    it 'waits between the iterations' do
      loop.__send__(:process_current_data)

      expect(loop).to have_received(:sleep).with(config.interval).once
    end
  end

  describe '#process_days',
           vcr: {
             cassette_name: 'loop-process_days',
             match_requests_on: %i[method uri flux_query],
           } do
    subject(:process) { loop.__send__(:process_days, day..day) }

    def day
      Date.new(2024, 6, 12)
    end

    before do
      noon = day.in_time_zone(config.time_zone) + 12.hours

      flux_write(
        (1..5).map do |minute|
          InfluxDB2::Point.new(
            name: 'SENEC',
            time: (noon + minute.minutes).to_i,
            fields: {
              'grid_power_plus' => 100,
              'house_power' => 70,
              'wallbox_charge_power' => 20,
              'bat_power_plus' => 10,
            },
          )
        end,
      )
    end

    # The split is written under the splitter's own measurement, which
    # flux_write never saw and flux_cleanup therefore does not know about.
    after do
      flux_deleter.delete_measurement(config.influx_measurement)
      flux_cleanup
    end

    it 'writes the split of that day' do
      expect { process }.to change { Flux::LastSplitter.new(config:).time }.from(
        nil,
      )
    end
  end

  # The ensure has to survive a reader that was never built, or the failure
  # arrives as a NoMethodError from the cleanup instead of as itself.
  describe '#process_days when the read cannot be started' do
    before { allow(ReadAhead).to receive(:new).and_raise('InfluxDB unreachable') }

    it 'lets the original failure through' do
      day = Date.new(2024, 6, 12)

      expect { loop.__send__(:process_days, day..day) }.to raise_error(
        'InfluxDB unreachable',
      )
    end
  end

  describe '#influx_ready?' do
    subject(:ready) { loop.__send__(:influx_ready?, 2) }

    before do
      stub_request(:get, %r{/ping}).to_timeout
      allow(loop).to receive(:sleep)
    end

    it 'gives up once the attempts are used up' do
      expect(ready).to be(false)
      expect(logger.error_messages.join).to include('not ready after 10 seconds')
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
        fetch_day: nil,
        records_from: [],
      )
      allow(RedisCache).to receive(:new).and_return(
        instance_double(RedisCache, flush: nil),
      )
      allow(PostgresSummaries).to receive(:new).and_return(postgres_summaries)
    end

    # Nothing is history yet, and the current day belongs to the endless loop
    # that runs right after this - processing it here would only do it twice.
    context 'when everything up to today is written' do
      before do
        allow(influx_pull).to receive(:last_splitter_date).and_return(
          Date.new(2025, 10, 14),
        )
      end

      it 'processes nothing' do
        loop.__send__(:process_historical_data)

        expect(postgres_summaries).not_to have_received(:reset)
      end
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

    let(:influx_pull) { instance_double(InfluxPull, fetch_day: nil, records_from: []) }

    before do
      allow(Date).to receive(:current).and_return(Date.new(2025, 10, 14))
      allow(InfluxPull).to receive(:new).and_return(influx_pull)
    end

    context 'when never run before' do
      let(:last_time) { nil }

      it 'processes nothing' do
        process

        expect(influx_pull).not_to have_received(:fetch_day)
      end
    end

    context 'when still on the same day' do
      let(:last_time) { Time.new(2025, 10, 14, 6, 0, 0) }

      it 'processes nothing' do
        process

        expect(influx_pull).not_to have_received(:fetch_day)
      end
    end

    context 'when the day just rolled over' do
      let(:last_time) { Time.new(2025, 10, 13, 23, 55, 0) }

      it 'completes yesterday' do
        process

        expect(influx_pull).to have_received(:fetch_day).with(
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

        expect(influx_pull).to have_received(:fetch_day).with(
          Date.new(2025, 10, 11).beginning_of_day,
        ).ordered
        expect(influx_pull).to have_received(:fetch_day).with(
          Date.new(2025, 10, 12).beginning_of_day,
        ).ordered
        expect(influx_pull).to have_received(:fetch_day).with(
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
# rubocop:enable RSpec/SubjectStub
