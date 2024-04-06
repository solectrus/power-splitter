require 'calculator'

describe Calculator do
  subject(:calculator) { described_class.new(day_records:, config:) }

  let(:config) { Config.new(ENV) }

  let(:day_records) do
    [
      {
        'time' => Time.new(2022, 1, 1, 12, 0, 0),
        'grid_power_plus' => 100,
        'house_power' => 50,
        'wallbox_charge_power' => 30,
        'power' => 20,
      },
      {
        'time' => Time.new(2022, 1, 1, 12, 30, 0),
        'grid_power_plus' => 200,
        'house_power' => 100,
        'wallbox_charge_power' => 60,
        'power' => 40,
      },
    ]
  end

  describe '#call' do
    subject(:call) { calculator.call }

    it 'returns the correct result' do
      expect(call).to be_a(Array)
      expect(call.first).to include(
        time: a_kind_of(Time),
        house_power_from_grid: 75,
        house_power_from_pv: 0,
        wallbox_power_from_grid: 45,
        wallbox_power_from_pv: 0,
        heatpump_power_from_grid: 30,
        heatpump_power_from_pv: 0,
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
