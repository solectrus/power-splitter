require 'processor'

describe Processor do
  subject(:processor) { described_class.new(day_records:, config:) }

  let(:config) { Config.new(ENV) }

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

  describe '#call' do
    subject(:call) { processor.call }

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

  describe '#call with battery tracking' do
    subject(:call) do
      described_class.new(day_records:, config:, battery_energy_grid:).call
    end

    let(:config) do
      Config.new(
        ENV.to_h.merge(
          'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER' => 'SENEC:bat_power_minus',
          'BATTERY_GRID_ATTRIBUTION' => 'true',
        ),
      )
    end
    let(:battery_energy_grid) { 0 }

    # 23:51 of one day until 00:10 of the next, so that the day boundary falls
    # right between two 5-minute periods.
    let(:midnight) { Time.new('2022-01-02 00:00:00 +01:00') }

    # 10 minutes of charging the battery from the grid at 3000 W (500 Wh),
    # then 10 minutes of running the heatpump off the battery at 2000 W.
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

    def field(point, name)
      point.instance_variable_get(:@fields)[name]
    end

    it 'fills the ledger while charging from the grid' do
      expect(field(call.first, 'battery_energy_grid')).to be_within(0.01).of(250)
      expect(field(call[1], 'battery_energy_grid')).to be_within(0.01).of(500)
    end

    it 'attributes the discharge to the heatpump' do
      expect(field(call[2], 'heatpump_power_grid')).to eq(2000)
      expect(field(call[3], 'heatpump_power_grid')).to eq(2000)
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

    # The ledger carries over between days, so processing a day on its own must
    # give the same result as processing it as part of a longer stretch.
    describe 'day boundary' do
      def process(records, seed)
        described_class.new(
          day_records: records,
          config:,
          battery_energy_grid: seed,
        ).call
      end

      it 'neither books a minute twice nor drops one' do
        first_day = process(day_records.select { |r| r['time'] <= midnight }, 0)
        second_day =
          process(
            day_records.select { |r| r['time'] > midnight },
            field(first_day.last, 'battery_energy_grid'),
          )

        expect((first_day + second_day).map(&:to_line_protocol)).to eq(
          call.map(&:to_line_protocol),
        )
      end
    end
  end
end
