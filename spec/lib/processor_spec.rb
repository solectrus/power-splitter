require 'processor'

describe Processor do
  subject(:processor) { described_class.new(day_records:, config:) }

  let(:config) { Config.new(ENV) }

  let(:day_records) do
    [
      {
        'time' => Time.new('2022-01-01 12:00:00 +01:00'),
        'SENEC:grid_power_plus' => 100,
        'SENEC:house_power' => 70,
        'SENEC:wallbox_charge_power' => 30,
        'SENEC:battery_charging_power' => 0,
        'Consumer:power' => 20,
      },
      {
        'time' => Time.new('2022-01-01 12:30:00 +01:00'),
        'SENEC:grid_power_plus' => 0,
        'SENEC:house_power' => 140,
        'SENEC:wallbox_charge_power' => 60,
        'SENEC:battery_charging_power' => 0,
        'Consumer:power' => 40,
      },
    ]
  end

  describe '#call' do
    subject(:call) { processor.call }

    it 'returns the correct result' do
      lines = call.map(&:to_line_protocol)

      expect(lines).to eq(
        [
          'power_splitter heatpump_power_grid=20i,house_power_grid=50i,wallbox_power_grid=30i 1641034800',
          'power_splitter heatpump_power_grid=0i,house_power_grid=0i,wallbox_power_grid=0i 1641036600',
        ],
      )
    end
  end
end
