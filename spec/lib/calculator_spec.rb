require 'calculator'

describe Calculator do
  subject(:calculator) { described_class.new(day_records:, config:) }

  let(:config) { Config.new(ENV) }

  let(:day_records) do
    [
      {
        'time' => Time.new('2022-01-01 12:00:00 +01:00'),
        'grid_power_plus' => 100,
        'house_power' => 70,
        'wallbox_charge_power' => 30,
        'power' => 20,
      },
      {
        'time' => Time.new('2022-01-01 12:30:00 +01:00'),
        'grid_power_plus' => 0,
        'house_power' => 140,
        'wallbox_charge_power' => 60,
        'power' => 40,
      },
    ]
  end

  describe '#call' do
    subject(:call) { calculator.call }

    it 'returns the correct result' do
      lines = call.map(&:to_line_protocol)

      expect(lines).to eq(
        [
          'my_power_splitter,origin=grid heatpump_power=10i,house_power=25i,wallbox_power=15i 1641034800',
          'my_power_splitter,origin=pv heatpump_power=20i,house_power=50i,wallbox_power=30i 1641034800',
        ],
      )
    end
  end

  describe '#split_power' do
    subject(:split_power) { calculator.send(:split_power, day_records.first) }

    it 'returns the correct result' do
      expect(split_power).to include(
        time: a_kind_of(Time),
        house_power_from_grid: 50,
        house_power_from_pv: 0,
        wallbox_power_from_grid: 30,
        wallbox_power_from_pv: 0,
        heatpump_power_from_grid: 20,
        heatpump_power_from_pv: 0,
      )
    end
  end
end
