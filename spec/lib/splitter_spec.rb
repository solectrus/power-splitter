require 'splitter'

describe Splitter do
  subject(:splitter) { described_class.new(config, **record) }

  let(:config) { Config.new(ENV) }

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
            battery_charging_power_grid: 0,
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
            battery_charging_power_grid: 0,
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

      it 'returns zero distribution' do
        expect(call).to eq(
          {
            house_power_grid: 0,
            heatpump_power_grid: 0,
            wallbox_power_grid: 0,
            battery_charging_power_grid: 0,
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

      it 'returns wallbox-first' do
        expect(call).to eq(
          {
            house_power_grid: 0,
            heatpump_power_grid: 0,
            wallbox_power_grid: 60,
            battery_charging_power_grid: 0,
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
            battery_charging_power_grid: 0,
          },
        )
      end
    end

    context 'when battery is charging from grid' do
      let(:record) do
        {
          # inverter_power: 100
          grid_import_power: 100,
          house_power: 10,
          heatpump_power: 30,
          wallbox_power: 30,
          battery_charging_power: 100,
        }
      end

      it 'returns battery-first' do
        expect(call).to eq(
          {
            house_power_grid: 5,
            heatpump_power_grid: 15,
            wallbox_power_grid: 30,
            battery_charging_power_grid: 50,
          },
        )
      end
    end

    context 'when battery is charging partly from grid' do
      let(:record) do
        {
          # inverter_power: 30
          grid_import_power: 30,
          house_power: 10,
          heatpump_power: 30,
          wallbox_power: 0,
          battery_charging_power: 20,
          # grid_export_power: 0
        }
      end

      it 'calculates' do
        expect(call).to eq(
          {
            house_power_grid: 5,
            heatpump_power_grid: 15,
            wallbox_power_grid: 0,
            battery_charging_power_grid: 10,
          },
        )
      end
    end

    context 'when battery is charging from PV' do
      let(:record) do
        {
          # inverter_power: 1000
          grid_import_power: 0,
          house_power: 10,
          heatpump_power: 30,
          wallbox_power: 60,
          battery_charging_power: 100,
          # grid_export_power: 800
        }
      end

      it 'returns all zero' do
        expect(call).to eq(
          {
            house_power_grid: 0,
            heatpump_power_grid: 0,
            wallbox_power_grid: 0,
            battery_charging_power_grid: 0,
          },
        )
      end
    end

    context 'when all is charged from grid' do
      let(:record) do
        {
          grid_import_power: 200,
          house_power: 50,
          heatpump_power: 20,
          wallbox_power: 30,
          battery_charging_power: 100,
        }
      end

      it 'returns full distribution' do
        expect(call).to eq(
          {
            house_power_grid: 50,
            heatpump_power_grid: 20,
            wallbox_power_grid: 30,
            battery_charging_power_grid: 100,
          },
        )
      end
    end

    context 'when wallbox and battery charging' do
      let(:record) do
        {
          # inverter_power: 2000
          grid_import_power: 21_000,
          wallbox_power: 21_000,
          house_power: 600,
          heatpump_power: 100,
          battery_charging_power: 1300,
        }
      end

      it 'returns wallbox-first' do
        expect(call).to eq(
          {
            battery_charging_power_grid: 0.0,
            heatpump_power_grid: 0.0,
            house_power_grid: 0.0,
            wallbox_power_grid: 21_000,
          },
        )
      end
    end

    context 'when custom power is given (100% consumption)' do
      let(:record) do
        {
          grid_import_power: 100,
          house_power: 100,
          heatpump_power: 0,
          wallbox_power: 0,
          battery_charging_power: 0,
          custom_power: [30, 30, nil],
        }
      end

      it 'distributes 100% to each consumer' do
        expect(call).to eq(
          {
            house_power_grid: 100,
            heatpump_power_grid: 0,
            wallbox_power_grid: 0,
            custom_power_01_grid: 30,
            custom_power_02_grid: 30,
            custom_power_03_grid: nil,
            battery_charging_power_grid: 0,
          },
        )
      end
    end

    context 'when custom power is given (10% consumption)' do
      let(:record) do
        {
          grid_import_power: 10,
          house_power: 100,
          heatpump_power: 0,
          wallbox_power: 0,
          battery_charging_power: 0,
          custom_power: [30, 30, nil],
        }
      end

      it 'distributes 10% to each consumer' do
        expect(call).to eq(
          {
            house_power_grid: 10,
            heatpump_power_grid: 0,
            wallbox_power_grid: 0,
            custom_power_01_grid: 3,
            custom_power_02_grid: 3,
            custom_power_03_grid: nil,
            battery_charging_power_grid: 0,
          },
        )
      end
    end

    context 'when custom power is given (some are nil)' do
      let(:record) do
        {
          grid_import_power: 10,
          house_power: 100,
          heatpump_power: 0,
          wallbox_power: 0,
          battery_charging_power: 0,
          custom_power: [60, nil, nil],
        }
      end

      it 'calculates' do
        expect(call).to eq(
          {
            house_power_grid: 10,
            heatpump_power_grid: 0,
            wallbox_power_grid: 0,
            custom_power_01_grid: 6,
            custom_power_02_grid: nil,
            custom_power_03_grid: nil,
            battery_charging_power_grid: 0,
          },
        )
      end
    end

    context 'when custom power is given (included consumers only)' do
      let(:record) do
        {
          grid_import_power: 10,
          house_power: 100,
          heatpump_power: 0,
          wallbox_power: 0,
          battery_charging_power: 0,
          custom_power: [50, 50, nil],
          # => Total consumption: 100 => 10% from grid
        }
      end

      it 'calculates' do
        expect(call).to eq(
          {
            house_power_grid: 10, # 100% of grid belongs to house
            heatpump_power_grid: 0,
            wallbox_power_grid: 0,
            custom_power_01_grid: 5,
            custom_power_02_grid: 5,
            custom_power_03_grid: nil,
            battery_charging_power_grid: 0,
          },
        )
      end
    end

    context 'when custom power is given (included and excluded consumer)' do
      let(:record) do
        {
          grid_import_power: 10,
          house_power: 100,
          heatpump_power: 0,
          wallbox_power: 0,
          battery_charging_power: 0,
          custom_power: [60, nil, 100],
          # Total consumption: 100 + 100 = 200 => 5% from grid
        }
      end

      it 'calculates' do
        expect(call).to eq(
          {
            house_power_grid: 5, # 5% of 100
            heatpump_power_grid: 0,
            wallbox_power_grid: 0,
            custom_power_01_grid: 3,
            custom_power_02_grid: nil,
            custom_power_03_grid: 5, # 5% of 100
            battery_charging_power_grid: 0,
          },
        )
      end
    end

    context 'when custom power is given (excluded consumer only)' do
      let(:record) do
        {
          grid_import_power: 10,
          house_power: 100,
          heatpump_power: 0,
          wallbox_power: 0,
          battery_charging_power: 0,
          custom_power: [nil, nil, 100],
          # Total consumption: 100 + 100 = 200 => 5% from grid
        }
      end

      it 'calculates' do
        expect(call).to eq(
          {
            house_power_grid: 5,
            heatpump_power_grid: 0,
            wallbox_power_grid: 0,
            custom_power_01_grid: nil,
            custom_power_02_grid: nil,
            custom_power_03_grid: 5,
            battery_charging_power_grid: 0,
          },
        )
      end
    end

    context 'when all is nil' do
      let(:record) do
        {
          grid_import_power: nil,
          house_power: nil,
          heatpump_power: nil,
          wallbox_power: nil,
          battery_charging_power: nil,
          custom_power: [nil, nil, nil],
        }
      end

      it 'returns nil for all fields' do
        expect(call).to eq(
          {
            heatpump_power_grid: nil,
            house_power_grid: nil,
            wallbox_power_grid: nil,
            custom_power_01_grid: nil,
            custom_power_02_grid: nil,
            custom_power_03_grid: nil,
            battery_charging_power_grid: nil,
          },
        )
      end
    end

    context 'when grid_import_power is nil' do
      let(:record) do
        {
          grid_import_power: nil,
          house_power: nil,
          heatpump_power: nil,
          wallbox_power: nil,
          battery_charging_power: 10,
          custom_power: [nil, nil, 10],
        }
      end

      it 'returns nil for all fields' do
        expect(call).to eq(
          {
            heatpump_power_grid: nil,
            house_power_grid: nil,
            wallbox_power_grid: nil,
            custom_power_01_grid: nil,
            custom_power_02_grid: nil,
            custom_power_03_grid: nil,
            battery_charging_power_grid: nil,
          },
        )
      end
    end
  end
end
