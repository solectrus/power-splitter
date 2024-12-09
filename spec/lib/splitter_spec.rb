require 'splitter'

describe Splitter do
  subject(:splitter) { described_class.new(**record) }

  describe '#call' do
    subject(:call) { splitter.call }

    context 'when grid is 100%' do
      let(:record) do
        {
          grid_import_power: 100,
          house_power: 50,
          heatpump_power: 20,
          wallbox_power: 30,
          battery_charging_power: 0,
        }
      end

      it 'returns full distribution' do
        expect(call).to eq(
          {
            house_power_grid: 50,
            heatpump_power_grid: 20,
            wallbox_power_grid: 30,
          },
        )
      end
    end

    context 'when grid is more than 100%' do
      let(:record) do
        {
          grid_import_power: 1000,
          house_power: 50,
          heatpump_power: 20,
          wallbox_power: 30,
          battery_charging_power: 0,
        }
      end

      it 'returns full distribution limited to consumption' do
        expect(call).to eq(
          {
            house_power_grid: 50,
            heatpump_power_grid: 20,
            wallbox_power_grid: 30,
          },
        )
      end
    end

    context 'when grid is 0%' do
      let(:record) do
        {
          grid_import_power: 0,
          house_power: 100,
          heatpump_power: 40,
          wallbox_power: 60,
          battery_charging_power: 0,
        }
      end

      it 'returns 0 distribution' do
        expect(call).to eq(
          {
            house_power_grid: 0,
            heatpump_power_grid: 0,
            wallbox_power_grid: 0,
          },
        )
      end
    end

    context 'when grid is 30%' do
      let(:record) do
        {
          grid_import_power: 60,
          house_power: 100,
          heatpump_power: 40,
          wallbox_power: 60,
          battery_charging_power: 0,
        }
      end

      it 'returns wallbox-first distribution' do
        expect(call).to eq(
          {
            house_power_grid: 0,
            heatpump_power_grid: 0,
            wallbox_power_grid: 60,
          },
        )
      end
    end

    context 'when grid is 60%' do
      let(:record) do
        {
          grid_import_power: 120,
          house_power: 20,
          heatpump_power: 60,
          wallbox_power: 40,
          battery_charging_power: 0,
        }
      end

      it 'returns wallbox-first, then others pro-rata' do
        expect(call).to eq(
          {
            house_power_grid: 20,
            heatpump_power_grid: 60,
            wallbox_power_grid: 40,
          },
        )
      end
    end

    context 'when battery is charging' do
      let(:record) do
        {
          # inverter_power: 100,
          grid_import_power: 100,
          house_power: 10,
          heatpump_power: 30,
          wallbox_power: 60,
          battery_charging_power: 100,
          # battery_discharging_power: 0,
        }
      end

      it 'returns battery-first' do
        expect(call).to eq(
          {
            house_power_grid: 0,
            heatpump_power_grid: 0,
            wallbox_power_grid: 0,
          },
        )
      end
    end
  end
end
