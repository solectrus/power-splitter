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

    # House power is mandatory, so a nil is a gap in the data. It is part of
    # the key the import is split by, and usually its largest term.
    context 'when house_power is nil' do
      let(:record) do
        {
          grid_import_power: 3000,
          house_power: nil,
          heatpump_power: 500,
          wallbox_power: 0,
          battery_charging_power: 0,
        }
      end

      it 'returns nil for all fields' do
        expect(call).to eq(
          {
            house_power_grid: nil,
            heatpump_power_grid: nil,
            wallbox_power_grid: nil,
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

  describe '#call with battery tracking' do
    subject(:call) { splitter.call }

    let(:config) do
      Config.new(
        ENV.to_h.merge(
          'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER' => 'SENEC:bat_power_minus',
          'BATTERY_GRID_ATTRIBUTION' => attribution,
        ),
      )
    end
    let(:attribution) { 'true' }

    # 1 minute at 2000 W is 33.33 Wh
    let(:full_discharge) do
      {
        grid_import_power: 0,
        house_power: 0,
        heatpump_power: 2000,
        wallbox_power: 0,
        battery_charging_power: 0,
        battery_discharging_power: 2000,
      }
    end

    context 'when the battery is charged from the grid' do
      let(:record) do
        {
          grid_import_power: 3300,
          house_power: 300,
          heatpump_power: 0,
          wallbox_power: 0,
          battery_charging_power: 3000,
          battery_discharging_power: 0,
          battery_energy_grid: 0,
        }
      end

      it 'books the grid share of the charging into the ledger' do
        expect(call).to include(
          battery_charging_power_grid: 3000,
          battery_energy_grid: 50, # 3000 W for 1 minute
        )
      end
    end

    context 'when the battery is charged from PV' do
      let(:record) do
        {
          grid_import_power: 0,
          house_power: 300,
          heatpump_power: 0,
          wallbox_power: 0,
          battery_charging_power: 3000,
          battery_discharging_power: 0,
          battery_energy_grid: 0,
        }
      end

      it 'leaves the ledger empty' do
        expect(call).to include(
          battery_charging_power_grid: 0,
          battery_energy_grid: 0,
        )
      end
    end

    context 'when discharging a battery holding grid energy' do
      let(:record) { full_discharge.merge(battery_energy_grid: 50) }

      it 'reports the heatpump as fully grid-powered' do
        expect(call).to include(heatpump_power_grid: 2000)
      end

      it 'debits the ledger by what was passed on' do
        expect(call[:battery_energy_grid]).to be_within(0.01).of(16.67)
      end

      it 'reports the grid share of the discharge' do
        expect(call[:battery_discharging_power_grid]).to be_within(0.01).of(2000)
      end
    end

    context 'when discharging a battery holding PV energy only' do
      let(:record) { full_discharge.merge(battery_energy_grid: 0) }

      it 'reports the heatpump as fully PV-powered' do
        expect(call).to include(
          heatpump_power_grid: 0,
          battery_energy_grid: 0,
        )
      end

      it 'reports no grid share of the discharge' do
        expect(call[:battery_discharging_power_grid]).to eq(0)
      end
    end

    context 'when discharging a battery holding a mix' do
      let(:record) { full_discharge.merge(battery_energy_grid: 16.665) }

      it 'splits the heatpump in half' do
        expect(call[:heatpump_power_grid]).to be_within(1).of(1000)
      end

      it 'empties the ledger' do
        expect(call[:battery_energy_grid]).to eq(0)
      end
    end

    # The reported grid share is what makes the consumers' grid values balance
    # again: they are fed from the import and from the battery.
    context 'when balancing the grid values' do
      let(:record) do
        full_discharge.merge(
          grid_import_power: 400,
          house_power: 300,
          wallbox_power: 500,
          battery_energy_grid: 1000,
        )
      end

      it 'accounts for the excess over the grid import' do
        consumer_grid =
          call.values_at(
            :house_power_grid,
            :heatpump_power_grid,
            :wallbox_power_grid,
            :battery_charging_power_grid,
          ).sum

        expect(consumer_grid).to be_within(0.01).of(
          record[:grid_import_power] + call[:battery_discharging_power_grid],
        )
      end
    end

    context 'when the discharge exceeds the current consumption' do
      let(:record) do
        full_discharge.merge(heatpump_power: 500, battery_energy_grid: 50)
      end

      it 'only pays out what reached the consumers' do
        expect(call).to include(heatpump_power_grid: 500)
        # 500 W for 1 minute is 8.33 Wh
        expect(call[:battery_energy_grid]).to be_within(0.01).of(41.67)
      end
    end

    context 'when the battery charges and discharges within the same minute' do
      let(:record) do
        {
          grid_import_power: 1200,
          house_power: 0,
          heatpump_power: 1200,
          wallbox_power: 0,
          battery_charging_power: 600,
          battery_discharging_power: 600,
          battery_energy_grid: 0,
        }
      end

      # Nothing is paid out, because the ledger was empty when the discharge
      # was booked. Had the deposit come first, it would have been paid out
      # again right away and the balance would have stayed at zero.
      it 'pays out before it books the deposit' do
        expect(call[:battery_energy_grid]).to be_within(0.01).of(6.67)
      end
    end

    context 'when attribution is disabled' do
      let(:attribution) { 'false' }
      let(:record) { full_discharge.merge(battery_energy_grid: 50) }

      it 'leaves the grid share of the consumers untouched' do
        expect(call).to include(heatpump_power_grid: 0)
      end

      it 'still tracks the ledger' do
        expect(call[:battery_energy_grid]).to be_within(0.01).of(16.67)
      end

      it 'does not report a grid share of the discharge' do
        expect(call).not_to have_key(:battery_discharging_power_grid)
      end
    end

    # Without the grid import nothing can be split, so the discharge must not
    # drain the ledger either - the grid energy would be gone without any
    # consumer having been credited with it.
    context 'when grid_import_power is nil' do
      let(:record) do
        full_discharge.merge(grid_import_power: nil, battery_energy_grid: 50)
      end

      it 'reports no grid share for the consumers' do
        expect(call).to include(heatpump_power_grid: nil)
      end

      it 'leaves the ledger untouched' do
        expect(call[:battery_energy_grid]).to eq(50)
      end

      # A zero would be the only term of the balance that survives averaging
      # over a period in which some minutes have no shares at all.
      it 'reports no grid share of the discharge' do
        expect(call).not_to have_key(:battery_discharging_power_grid)
      end
    end

    context 'when house_power is nil' do
      let(:record) do
        full_discharge.merge(house_power: nil, battery_energy_grid: 50)
      end

      it 'reports no grid share for the consumers' do
        expect(call).to include(heatpump_power_grid: nil)
      end

      it 'reports no grid share of the discharge' do
        expect(call).not_to have_key(:battery_discharging_power_grid)
      end
    end

    # The wallbox is served first and would otherwise be the one consumer that
    # still gets a share - draining the ledger all by itself.
    context 'when grid_import_power is nil while the wallbox runs' do
      let(:record) do
        full_discharge.merge(
          grid_import_power: nil,
          wallbox_power: 1500,
          battery_energy_grid: 50,
        )
      end

      it 'reports no grid share for the wallbox either' do
        expect(call).to include(wallbox_power_grid: nil)
      end

      it 'leaves the ledger untouched' do
        expect(call[:battery_energy_grid]).to eq(50)
      end
    end

    context 'when the wallbox competes with the heatpump' do
      let(:record) do
        full_discharge.merge(wallbox_power: 1500, battery_energy_grid: 1000)
      end

      # The whole discharge is grid-sourced here, so the shares show through
      it 'serves the wallbox first, as it does for grid import' do
        expect(call).to include(
          wallbox_power_grid: 1500,
          heatpump_power_grid: 500,
        )
      end
    end
  end
end
