require 'processor'
require 'config'

# The rules the calculation has to obey, whatever the data looks like.
#
# They are checked against randomly generated days rather than against a handful
# of hand-picked ones: what broke these rules in the past were always the cases
# nobody thought of - a sensor dropping out for two minutes, a gap ending in the
# middle of a period, a day starting hours late. CALCULATION.md says what the
# rules mean; this is where they are executed.
#
# The random seed is fixed, so a run either passes or fails for everyone. Raise
# the number of cases or change the seed locally to search further.
describe 'Invariants' do
  let(:config) do
    Config.new(
      {
        'INFLUX_HOST' => 'localhost',
        'INFLUX_TOKEN' => 'token',
        'INFLUX_ORG' => 'org',
        'INFLUX_BUCKET' => 'bucket',
        'TZ' => 'Europe/Berlin',
        'INFLUX_SENSOR_GRID_IMPORT_POWER' => 'SENEC:grid_power_plus',
        'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
        'INFLUX_SENSOR_HEATPUMP_POWER' => 'Heatpump:power',
        'INFLUX_SENSOR_WALLBOX_POWER' => 'SENEC:wallbox_charge_power',
        'INFLUX_SENSOR_BATTERY_CHARGING_POWER' => 'SENEC:bat_power_plus',
        'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER' => 'SENEC:bat_power_minus',
        'INFLUX_EXCLUDE_FROM_HOUSE_POWER' => 'HEATPUMP_POWER,WALLBOX_POWER',
      },
    )
  end

  let(:midnight) { Time.new('2024-06-12 00:00:00 +02:00') }

  # Every sensor of this configuration. Custom sensors are left out entirely:
  # those that are part of house power are a breakdown of it rather than an
  # addition, and would only blur what the sum below is about.
  let(:sensors) do
    [
      'SENEC:grid_power_plus',
      'SENEC:house_power',
      'Heatpump:power',
      'SENEC:wallbox_charge_power',
      'SENEC:bat_power_plus',
      'SENEC:bat_power_minus',
    ]
  end

  # The consumers that draw from the grid import - what their shares have to
  # add up to.
  let(:consumers) do
    %w[
      house_power_grid
      heatpump_power_grid
      wallbox_power_grid
      battery_charging_power_grid
    ]
  end

  # Every field is rounded to a whole watt on its own, so a sum of five of them
  # can be off by that much.
  let(:tolerance) { 3 }

  # Runs the block against a series of random days. The seed of each run is
  # derived from the fixed one, so a failure is reproducible.
  def cases(count = 50)
    random = Random.new(20_240_827)

    count.times { yield random }
  end

  # One minute of a plausible installation. The grid import stays below what
  # the consumers actually draw: above that, the surplus has nobody to go to,
  # and no rule can distribute what nobody takes.
  def minute(time, random)
    house_rest = random.rand(0..3000)
    heatpump = random.rand(0..3000)
    wallbox = random.rand(0..11_000)
    charging = random.rand(0..5000)

    {
      'time' => time,
      'SENEC:grid_power_plus' =>
        random.rand(0..(house_rest + heatpump + wallbox + charging)),
      'SENEC:house_power' => house_rest + heatpump + wallbox,
      'Heatpump:power' => heatpump,
      'SENEC:wallbox_charge_power' => wallbox,
      'SENEC:bat_power_plus' => charging,
      'SENEC:bat_power_minus' => charging.positive? ? 0 : random.rand(0..5000),
    }
  end

  # A stretch of minutes, with sensors dropping out here and there - which is
  # what a sensor silent past MAX_AGE looks like by the time it gets here.
  def stretch(random, start: midnight, minutes: 60, droppable: [])
    Array.new(minutes) do |i|
      minute(start + i.minutes, random).tap do |record|
        droppable.each { |sensor| record.delete(sensor) if random.rand < 0.1 }
      end
    end
  end

  # The day is what the loop hands over, not something the records are asked
  # for: the ledger starts at its boundary, and a stretch reaching back into the
  # day before starts behind a gap.
  def process(records, seed = 0, day: midnight.to_date)
    Processor.new(
      day:,
      day_records: records,
      config:,
      battery_energy_grid: seed,
    ).call
  end

  def fields(point)
    point.instance_variable_get(:@fields)
  end

  def time_of(point)
    point.instance_variable_get(:@time)
  end

  # Pairs every period with the minutes it was calculated from.
  def periods(records, points)
    points.map do |point|
      center = Time.zone.at(time_of(point))

      [
        point,
        records.select do |record|
          record['time'] > center - 2.5.minutes &&
            record['time'] <= center + 2.5.minutes
        end,
      ]
    end
  end

  # The minutes a period is averaged over: those in which the split could
  # happen at all. Stated in terms of the sensors here, while the calculation
  # derives it from what came out of the split.
  def import_average(records)
    minutes =
      records.select do |record|
        record['SENEC:grid_power_plus'] && record['SENEC:house_power']
      end
    return 0 if minutes.empty?

    minutes.sum { |record| record['SENEC:grid_power_plus'] }.fdiv(minutes.size)
  end

  def consumer_sum(point)
    consumers.sum { |key| fields(point)[key] || 0 }
  end

  def discharge_share(point)
    fields(point)['battery_discharging_power_grid'] || 0
  end

  before { Time.zone = 'Europe/Berlin' }

  # Grid electricity reaches a consumer either directly or through the battery,
  # and there is no third source. SOLECTRUS scales these fields so that they add
  # up exactly, so they have to be close before it starts.
  describe 'the consumers add up to what came in' do
    # Any sensor can drop out, the battery included. Then part of the import has
    # nobody left to go to and stays undistributed - which may lower the sum,
    # never raise it.
    it 'never hands out more than came in' do
      cases do |random|
        records = stretch(random, droppable: sensors)

        periods(records, process(records)).each do |point, minutes|
          expect(consumer_sum(point)).to be <=
            import_average(minutes) + discharge_share(point) + tolerance
        end
      end
    end

    # With every consumer of the import known, nothing may be left over. This is
    # the balance SOLECTRUS scales against: a share missing here is a share it
    # would scale away from the others.
    it 'hands out everything that came in' do
      cases do |random|
        records =
          stretch(random, droppable: sensors - ['SENEC:bat_power_plus'])

        periods(records, process(records)).each do |point, minutes|
          expect(consumer_sum(point)).to be_within(tolerance).of(
            import_average(minutes) + discharge_share(point),
          )
        end
      end
    end
  end

  # The ledger says how much grid electricity is sitting in the battery. It can
  # only hold what was put in, and an empty one has nothing to hand out.
  describe 'the ledger holds what was put in' do
    it 'stays between zero and what was charged from the grid' do
      cases do |random|
        records = stretch(random, droppable: ['SENEC:bat_power_minus'])
        charged = 0.0

        process(records).each do |point|
          charged +=
            (fields(point)['battery_charging_power_grid'] || 0) * 5.fdiv(60)

          expect(fields(point)['battery_energy_grid']).to be_between(
            0,
            charged + tolerance,
          )
        end
      end
    end
  end

  # After a gap nothing is known about what the battery did in between, so a
  # balance from before it would be a guess. Nothing is imported after the gap
  # here, so nothing can be booked either: whatever the day was seeded with, the
  # ledger has to stay empty.
  describe 'a gap empties the ledger' do
    it 'pays out nothing that was measured before the gap' do
      cases do |random|
        gap_ends = midnight + 2.hours
        records =
          stretch(random, minutes: 30) +
            stretch(random, start: gap_ends, minutes: 30).map do |record|
              record.merge('SENEC:grid_power_plus' => 0)
            end

        process(records, random.rand(0..5000))
          .select { |point| time_of(point) >= gap_ends.to_i }
          .each do |point|
            expect(fields(point)['battery_energy_grid']).to eq(0)
            expect(discharge_share(point)).to eq(0)
          end
      end
    end
  end

  # A day is calculated on its own, seeded with the balance the day before ended
  # on. That has to give the same result as calculating both in one go -
  # otherwise the numbers would depend on when the splitter happened to run.
  describe 'a day can be calculated on its own' do
    it 'gives the same result as one long stretch' do
      cases do |random|
        records = stretch(random, start: midnight - 30.minutes)
        first, second = records.partition { |record| record['time'] <= midnight }
        day_before = (midnight - 1.day).to_date

        yesterday = process(first, day: day_before)
        today = process(second, fields(yesterday.last)['battery_energy_grid'])

        expect((yesterday + today).map(&:to_line_protocol)).to eq(
          process(records, day: day_before).map(&:to_line_protocol),
        )
      end
    end
  end

  # InfluxDB settles the type of a field the first time it is written and
  # refuses a later value of another type. What comes out of here is therefore
  # not just a number but a number of a kind: the powers are whole watts, the
  # ledger balance is not.
  #
  # Nothing above would notice the difference. They compare values, and 100
  # equals 100.0 - only the database says otherwise, on an installation that
  # has been writing the old type for years.
  describe 'the fields keep their type' do
    it 'writes whole watts, and the ledger balance as a float' do
      cases do |random|
        records = stretch(random, droppable: sensors)

        process(records).each do |point|
          powers = fields(point).except('battery_energy_grid')

          expect(powers.values).to all(be_an(Integer))
          expect(fields(point)['battery_energy_grid']).to be_a(Float)
        end
      end
    end
  end
end
