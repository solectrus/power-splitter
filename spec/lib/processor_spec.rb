require 'processor'

describe Processor do
  subject(:processor) { described_class.new(day_records:, config:) }

  let(:beginning) { Time.new('2022-01-01 12:01:00 +01:00') }

  describe '#call' do
    subject(:call) { processor.call }

    context 'with balcony solar power' do
      let(:config) { Config.new(ENV) }

      let(:day_records) do
        [
          # 12:01 - 12:05
          *Array.new(5) do |i|
            {
              'time' => beginning + i.minutes,
              'SENEC:inverter_power' => 1000,
              'balcony:inverter_power' => 0,
              'SENEC:grid_power_plus' => 100,
              'SENEC:grid_power_minus' => 0,
              'SENEC:bat_power_plus' => 10,
              'SENEC:bat_power_minus' => 0,
              'SENEC:wallbox_charge_power' => 20,
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
              'SENEC:inverter_power' => 0,
              'balcony:inverter_power' => 0,
              'SENEC:grid_power_plus' => 0,
              'SENEC:grid_power_minus' => 0,
              'SENEC:house_power' => 140,
              'SENEC:wallbox_charge_power' => 60,
              'SENEC:bat_power_plus' => 0,
              'SENEC:bat_power_minus' => 0,
              'Heatpump:power' => 40,
              'Consumer-01:power' => 10,
              'Consumer-02:power' => 5,
              'Consumer-20:power' => 12,
            }
          end,
        ]
      end

      it 'returns the correct result' do
        lines = call.map(&:to_line_protocol)

        expect(lines).to eq(
          [
            'power_splitter battery_charging_power_grid=1i,custom_power_01_grid=1i,custom_power_02_grid=0i,custom_power_20_grid=1i,heatpump_power_grid=1i,house_power=1050i,house_power_grid=78i,wallbox_power_grid=20i 1641034950',
            'power_splitter battery_charging_power_grid=0i,custom_power_01_grid=0i,custom_power_02_grid=0i,custom_power_20_grid=0i,heatpump_power_grid=0i,house_power=0i,house_power_grid=0i,wallbox_power_grid=0i 1641036750',
          ],
        )
      end
    end

    context 'without balcony solar power' do
      let(:config) do
        Config.new(
          ENV.except(
            'INFLUX_SENSOR_INVERTER_POWER',
            'INFLUX_SENSOR_BALCONY_INVERTER_POWER',
            'INFLUX_SENSOR_GRID_EXPORT_POWER',
            'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER',
          ),
        )
      end

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
  end
end
