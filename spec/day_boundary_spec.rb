require 'flux/extractor'
require 'processor'
require 'config'

# The seam where the calculation has broken before: a day is read from InfluxDB
# on its own, split on its own, and seeded with the balance the day before ended
# on. Whether that balance may be used depends on something the day itself
# cannot see - whether the data ran through midnight or stopped somewhere before
# it. Both cases are exercised here the way the loop does it and against a real
# query, because the mistakes lived in the query rather than in the split.
describe 'Day boundary' do # rubocop:disable RSpec/DescribeClass
  let(:config) do
    Config.new(
      ENV.to_h.merge(
        'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER' => 'SENEC:bat_power_minus',
      ),
    )
  end

  let(:extractor) { Flux::Extractor.new(config:) }

  let(:yesterday) { Date.new(2024, 6, 11) }
  let(:today) { Date.new(2024, 6, 12) }

  # Charging the battery from the grid: 3000 W for a minute is 50 Wh of grid
  # electricity booked into the ledger.
  def charging(time)
    point(
      time,
      'grid_power_plus' => 3300,
      'house_power' => 300,
      'bat_power_plus' => 3000,
      'bat_power_minus' => 0,
    )
  end

  # Running the house off the battery, with nothing coming from the grid.
  def discharging(time)
    point(
      time,
      'grid_power_plus' => 0,
      'house_power' => 2000,
      'bat_power_plus' => 0,
      'bat_power_minus' => 2000,
    )
  end

  def point(time, fields)
    InfluxDB2::Point.new(name: 'SENEC', time: time.to_i, fields:)
  end

  # Every minute between two offsets into the day.
  def minutes(day, from:, to:)
    start = day.in_time_zone(config.time_zone)

    ((from.to_i / 60)..(to.to_i / 60)).map { |minute| start + minute.minutes }
  end

  def fields(result)
    result.instance_variable_get(:@fields)
  end

  # A day, calculated the way Loop does it: the balance the day before ended on
  # is what this one starts from.
  def process(day, seed)
    Processor.new(
      day:,
      day_records: extractor.records(extractor.fetch(day)),
      config:,
      battery_energy_grid: seed,
    ).call
  end

  def balance_of(day, seed = 0)
    fields(process(day, seed).last)['battery_energy_grid']
  end

  after { flux_cleanup }

  # Data that stops before midnight and comes back hours later. The balance of
  # the day before is still there to be found - and must not be used.
  context 'when a gap runs over midnight',
          vcr: {
            cassette_name: 'day_boundary-with-gap',
            match_requests_on: %i[method uri flux_query],
          } do
    before do
      charged = minutes(yesterday, from: 19.hours, to: 21.hours)
      discharged = minutes(today, from: 90.minutes, to: 150.minutes)

      flux_write(
        charged.map { charging(it) } + discharged.map { discharging(it) },
      )
    end

    it 'starts the day behind the gap' do
      expect(extractor.records(extractor.fetch(today)).first['time']).to eq(
        today.in_time_zone(config.time_zone) + 91.minutes,
      )
    end

    it 'starts the ledger empty and attributes nothing to the grid' do
      seed = balance_of(yesterday)
      expect(seed).to be_positive # what the day would be seeded with

      results = process(today, seed).map { |result| fields(result) }

      expect(results.map { it['battery_energy_grid'] }).to all(eq(0))
      expect(results.map { it['battery_discharging_power_grid'] }).to all(eq(0))
    end
  end

  # The same stretch without the gap: here the balance describes the battery as
  # it really is, and the day after may pay it out.
  context 'when the data runs through midnight',
          vcr: {
            cassette_name: 'day_boundary-continuous',
            match_requests_on: %i[method uri flux_query],
          } do
    before do
      charged =
        minutes(yesterday, from: 23.hours + 30.minutes, to: 23.hours + 59.minutes)
      discharged = minutes(today, from: 0, to: 60.minutes)

      flux_write(
        charged.map { charging(it) } + discharged.map { discharging(it) },
      )
    end

    it 'starts the day at its first minute' do
      expect(extractor.records(extractor.fetch(today)).first['time']).to eq(
        today.in_time_zone(config.time_zone) + 1.minute,
      )
    end

    it 'pays out what the day before put into the battery' do
      # 30 minutes of charging at 3000 W
      seed = balance_of(yesterday)
      expect(seed).to be_within(0.01).of(1500)

      results = process(today, seed).map { |result| fields(result) }

      # The house runs off the battery, and the battery holds grid electricity
      expect(results.first['battery_discharging_power_grid']).to eq(2000)
      expect(results.first['house_power_grid']).to eq(2000)

      # 2000 W empty the ledger in 45 minutes, and nothing is attributed after
      expect(results.last['battery_energy_grid']).to eq(0)
      expect(results.last['battery_discharging_power_grid']).to eq(0)
    end
  end
end
