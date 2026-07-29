require 'processor'

describe Processor do
  subject(:call) do
    described_class.new(day:, day_records:, config:, battery_energy_grid:).call
  end

  let(:config) { Config.new(ENV) }
  let(:battery_energy_grid) { 0 }
  let(:day) { Date.new(2022, 1, 1) }
  let(:beginning) { Time.new('2022-01-01 12:01:00 +01:00') }

  let(:day_records) do
    [
      # 12:01 - 12:05
      *Array.new(5) do |i|
        {
          'time' => beginning + i.minutes,
          'SENEC:grid_power_plus' => 100,
          'SENEC:house_power' => 70,
          'SENEC:wallbox_charge_power' => 20,
          'SENEC:bat_power_plus' => 10,
          'Heatpump:power' => 20,
          'Consumer-01:power' => 10,
          'Consumer-02:power' => 5,
          'Consumer-20:power' => 12,
        }
      end,
      # 12:31 - 12:35
      *Array.new(5) do |i|
        {
          'time' => beginning + 30.minutes + i.minutes,
          'SENEC:grid_power_plus' => 0,
          'SENEC:house_power' => 140,
          'SENEC:wallbox_charge_power' => 60,
          'SENEC:bat_power_plus' => 0,
          'Heatpump:power' => 40,
          'Consumer-01:power' => 10,
          'Consumer-02:power' => 5,
          'Consumer-20:power' => 12,
        }
      end,
    ]
  end

  def midnight
    Time.new('2022-01-02 00:00:00 +01:00')
  end

  def fields(point)
    point.instance_variable_get(:@fields)
  end

  def field(point, name)
    fields(point)[name]
  end

  describe '#call' do
    it 'returns the correct result' do
      lines = call.map(&:to_line_protocol)

      expect(lines).to eq(
        [
          'power_splitter battery_charging_power_grid=10i,custom_power_01_grid=10i,custom_power_02_grid=5i,custom_power_20_grid=12i,heatpump_power_grid=20i,house_power_grid=30i,wallbox_power_grid=20i 1641034950',
          'power_splitter battery_charging_power_grid=0i,custom_power_01_grid=0i,custom_power_02_grid=0i,custom_power_20_grid=0i,heatpump_power_grid=0i,house_power_grid=0i,wallbox_power_grid=0i 1641036750',
        ],
      )
    end
  end

  # Minutes can be missing, so a period is not always covered completely. Its
  # point still belongs to the center of the period - deriving the timestamp
  # from the last record would push a group that ends early out of its period,
  # right after midnight even into the previous day.
  describe '#call with an incomplete period' do
    let(:day_records) do
      [
        {
          'time' => midnight + 1.minute,
          'SENEC:grid_power_plus' => 100,
          'SENEC:house_power' => 100,
        },
      ]
    end

    it 'stamps the point at the center of its period' do
      expect(call.first.to_line_protocol).to end_with(
        " #{(midnight + 2.5.minutes).to_i}",
      )
    end
  end

  # A sensor silent past MAX_AGE arrives as a missing value rather than as a
  # flat line, so house power can be absent while the grid import goes on.
  describe '#call without house power' do
    let(:day_records) do
      Array.new(5) do |i|
        {
          'time' => beginning + i.minutes,
          'SENEC:grid_power_plus' => 3000,
          'Heatpump:power' => 500,
        }
      end
    end

    # Reading the missing house power as zero would hand the whole import to
    # the heatpump instead - the split is proportional to what the consumers
    # draw, and without the largest of them there is nothing to divide by.
    it 'reports no grid share at all' do
      expect(fields(call.first)).to eq({})
    end
  end

  # A gap can end in the middle of a period, leaving a field present for some
  # of its minutes only.
  describe '#call with a partly covered period' do
    let(:day_records) do
      Array.new(5) do |i|
        {
          'time' => beginning + i.minutes,
          'SENEC:house_power' => 1000,
          # The grid data only starts in the middle of the period
          **(i < 2 ? {} : { 'SENEC:grid_power_plus' => 1000 }),
        }
      end
    end

    it 'averages over the minutes the split covers' do
      expect(fields(call.first)['house_power_grid']).to eq(1000)
    end
  end

  # A consumer can be missing while the split goes on: only its own sensor is
  # silent, the grid import and house power that the split rests on are there.
  describe '#call with a consumer missing part of the period' do
    let(:day_records) do
      Array.new(5) do |i|
        {
          'time' => beginning + i.minutes,
          'SENEC:grid_power_plus' => 1000,
          'SENEC:house_power' => 3000,
          # The heatpump reports in the first minute only
          **(i.zero? ? { 'Heatpump:power' => 2000 } : {}),
        }
      end
    end

    # Averaging its share over its own minute alone would report it as if it
    # had drawn that power for the whole period, and the consumers would add up
    # to more than was imported.
    it 'keeps the consumers adding up to the grid import' do
      expect(
        fields(call.first).values_at('house_power_grid', 'heatpump_power_grid'),
      ).to eq([867, 133])
    end
  end

  describe '#call with battery tracking' do
    let(:config) do
      Config.new(
        ENV.to_h.merge(
          'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER' => 'SENEC:bat_power_minus',
          'BATTERY_GRID_ATTRIBUTION' => 'true',
        ),
      )
    end

    # 23:51 of one day until 00:10 of the next, so that the day boundary falls
    # right between two 5-minute periods: 10 minutes of charging the battery
    # from the grid at 3000 W (500 Wh), then 10 minutes of running the heatpump
    # off the battery at 2000 W.
    let(:day_records) do
      [
        *Array.new(10) { |i| charging(midnight - 9.minutes + i.minutes) },
        *Array.new(10) { |i| discharging(midnight + 1.minute + i.minutes) },
      ]
    end

    def charging(time)
      {
        'time' => time,
        'SENEC:grid_power_plus' => 3300,
        'SENEC:house_power' => 300,
        'SENEC:bat_power_plus' => 3000,
        'SENEC:bat_power_minus' => 0,
        'Heatpump:power' => 0,
      }
    end

    def discharging(time)
      {
        'time' => time,
        'SENEC:grid_power_plus' => 0,
        'SENEC:house_power' => 2000,
        'SENEC:bat_power_plus' => 0,
        'SENEC:bat_power_minus' => 2000,
        'Heatpump:power' => 2000,
      }
    end

    it 'fills the ledger while charging from the grid' do
      expect(field(call.first, 'battery_energy_grid')).to be_within(0.01).of(250)
      expect(field(call[1], 'battery_energy_grid')).to be_within(0.01).of(500)
    end

    it 'attributes the discharge to the heatpump' do
      expect(field(call[2], 'heatpump_power_grid')).to eq(2000)
      expect(field(call[3], 'heatpump_power_grid')).to eq(2000)
    end

    # Unlike the ledger balance, this is a power and gets averaged over the
    # period rather than carried over.
    it 'reports the grid share of the discharge' do
      expect(field(call.first, 'battery_discharging_power_grid')).to eq(0)
      expect(field(call[2], 'battery_discharging_power_grid')).to eq(2000)
    end

    it 'empties the ledger by what the heatpump consumed' do
      # 10 minutes at 2000 W is 333.33 Wh, leaving 166.67 Wh
      expect(field(call.last, 'battery_energy_grid')).to be_within(0.01).of(
        166.67,
      )
    end

    context 'when the battery holds PV energy only' do
      let(:day_records) do
        Array.new(10) { |i| discharging(midnight + 1.minute + i.minutes) }
      end

      it 'attributes nothing to the grid' do
        expect(field(call.first, 'heatpump_power_grid')).to eq(0)
      end
    end

    # The grid share of the discharge is what makes the consumers' shares add
    # up, so it has to be averaged over exactly the minutes that carry them.
    context 'when only some minutes of a period can be split' do
      let(:battery_energy_grid) { 1000 }

      let(:day_records) do
        Array.new(5) do |i|
          discharging(midnight + 1.minute + i.minutes).tap do |record|
            record.delete('SENEC:house_power') if i >= 2
          end
        end
      end

      it 'balances the consumers against import and discharge' do
        consumers =
          field(call.first, 'house_power_grid') +
            field(call.first, 'heatpump_power_grid')

        expect(consumers).to eq(
          field(call.first, 'battery_discharging_power_grid'),
        )
      end
    end

    # A gap says nothing about what the battery did in between, so a balance
    # from before it would be a guess. The day boundary is not special here.
    context 'when a gap splits the stretch' do
      let(:day_records) do
        [
          *Array.new(10) { |i| charging(midnight - 9.minutes + i.minutes) },
          # Three hours later, which is past the carry-forward window
          *Array.new(10) do |i|
            discharging(midnight + 3.hours + 1.minute + i.minutes)
          end,
        ]
      end

      it 'starts the ledger empty again' do
        expect(field(call[1], 'battery_energy_grid')).to be_within(0.01).of(500)
        expect(field(call.last, 'battery_energy_grid')).to eq(0)
      end

      it 'attributes nothing to the grid after the gap' do
        expect(field(call[2], 'heatpump_power_grid')).to eq(0)
      end
    end

    # The seed describes the state at the day boundary, so a day whose records
    # start hours later sits behind a gap just as much as one interrupted in
    # the middle.
    context 'when the day starts behind a gap' do
      let(:battery_energy_grid) { 1000 }

      let(:day_records) do
        Array.new(5) { |i| discharging(midnight + 3.hours + i.minutes) }
      end

      it 'starts the ledger empty' do
        expect(field(call.first, 'battery_energy_grid')).to eq(0)
        expect(field(call.first, 'heatpump_power_grid')).to eq(0)
      end
    end

    # A record is stamped at the end of the minute it covers, so the last one of
    # a day carries the timestamp of the next midnight. Data returning at 23:59
    # after a day-long outage leaves a day holding nothing else - and that one
    # record sits a whole day behind the boundary the seed describes.
    context 'when the day holds nothing but its last record' do
      let(:battery_energy_grid) { 5000 }

      let(:day_records) { [discharging(midnight)] }

      it 'starts the ledger empty' do
        expect(field(call.first, 'battery_energy_grid')).to eq(0)
        expect(field(call.first, 'battery_discharging_power_grid')).to eq(0)
        expect(field(call.first, 'heatpump_power_grid')).to eq(0)
      end
    end

    # Silence shorter than the carry-forward window arrives as records holding
    # the last value, so a minute missing between two others is already a gap
    # wider than that window - no matter how short it looks.
    context 'when a single minute is missing' do
      let(:day_records) do
        [
          *Array.new(10) { |i| charging(midnight - 9.minutes + i.minutes) },
          *Array.new(10) { |i| discharging(midnight + 2.minutes + i.minutes) },
        ]
      end

      it 'starts the ledger empty again' do
        expect(field(call[1], 'battery_energy_grid')).to be_within(0.01).of(500)
        expect(field(call.last, 'battery_energy_grid')).to eq(0)
      end
    end

    # A record stays as long as any sensor still reports, so losing one of those
    # the ledger is built from is a gap that leaves no hole in the records. By
    # the time a value is dropped its sensor has been silent for two hours, in
    # which the battery may have been emptied unseen.
    context 'when a record lost the discharging sensor' do
      let(:day_records) do
        [
          *Array.new(10) { |i| charging(midnight - 9.minutes + i.minutes) },
          *Array.new(10) do |i|
            discharging(midnight + 1.minute + i.minutes).tap do |record|
              record.delete('SENEC:bat_power_minus') if i.zero?
            end
          end,
        ]
      end

      it 'starts the ledger empty again' do
        expect(field(call[1], 'battery_energy_grid')).to be_within(0.01).of(500)
        expect(field(call[2], 'battery_energy_grid')).to eq(0)
        expect(field(call.last, 'battery_energy_grid')).to eq(0)
      end

      it 'attributes nothing to the grid afterwards' do
        expect(field(call[2], 'heatpump_power_grid')).to eq(0)
        expect(field(call[3], 'heatpump_power_grid')).to eq(0)
      end
    end

    # The ledger carries over between days, so processing a day on its own must
    # give the same result as processing it as part of a longer stretch.
    describe 'day boundary' do
      def process(records, seed, day)
        described_class.new(
          day:,
          day_records: records,
          config:,
          battery_energy_grid: seed,
        ).call
      end

      it 'neither books a minute twice nor drops one' do
        first_day =
          process(day_records.select { |r| r['time'] <= midnight }, 0, day)
        second_day =
          process(
            day_records.select { |r| r['time'] > midnight },
            field(first_day.last, 'battery_energy_grid'),
            day + 1,
          )

        expect((first_day + second_day).map(&:to_line_protocol)).to eq(
          call.map(&:to_line_protocol),
        )
      end
    end
  end
end
