require 'config'

describe Config do
  let(:config) { described_class.new(env) }

  let(:valid_env) do
    {
      'INFLUX_HOST' => 'influx.example.com',
      'INFLUX_SCHEMA' => 'https',
      'INFLUX_PORT' => '443',
      'INFLUX_TOKEN' => 'this.is.just.an.example',
      'INFLUX_ORG' => 'solectrus',
      'INFLUX_BUCKET' => 'my-bucket',
      ###
      'POWER_SPLITTER_INTERVAL' => '600',
      ###
      'INSTALLATION_DATE' => '2021-01-01',
      ###
      'INFLUX_SENSOR_GRID_IMPORT_POWER' => 'SENEC:grid_power_plus',
      'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
      'INFLUX_SENSOR_WALLBOX_POWER' => 'SENEC:wallbox_charge_power',
      'INFLUX_SENSOR_HEATPUMP_POWER' => 'Consumer:power',
      'INFLUX_SENSOR_BATTERY_CHARGING_POWER' => 'SENEC:bat_power_plus',
      'INFLUX_EXCLUDE_FROM_HOUSE_POWER' => 'HEATPUMP_POWER,WALLBOX_POWER',
    }
  end

  describe 'valid options' do
    let(:env) { valid_env }

    it 'initializes successfully' do
      expect(config).to be_a(described_class)
    end
  end

  describe 'valid options (no wallbox)' do
    let(:env) do
      valid_env.except('INFLUX_SENSOR_WALLBOX_POWER').merge(
        'INFLUX_EXCLUDE_FROM_HOUSE_POWER' => 'HEATPUMP_POWER',
      )
    end

    it 'initializes successfully' do
      expect(config).to be_a(described_class)
    end
  end

  describe 'valid options (no heatpump)' do
    let(:env) do
      valid_env.except('INFLUX_SENSOR_HEATPUMP_POWER').merge(
        'INFLUX_EXCLUDE_FROM_HOUSE_POWER' => 'WALLBOX_POWER',
      )
    end

    it 'initializes successfully' do
      expect(config).to be_a(described_class)
    end
  end

  describe 'valid options (empty heatpump)' do
    let(:env) do
      valid_env.merge('INFLUX_SENSOR_HEATPUMP_POWER' => '').merge(
        'INFLUX_EXCLUDE_FROM_HOUSE_POWER' => 'WALLBOX_POWER',
      )
    end

    it 'initializes successfully' do
      expect(config).to be_a(described_class)
    end
  end

  describe 'valid options (custom sensors)' do
    let(:env) do
      valid_env.merge(
        'INFLUX_SENSOR_CUSTOM_POWER_02' => 'm:f',
        'INFLUX_EXCLUDE_FROM_HOUSE_POWER' =>
          'HEATPUMP_POWER,WALLBOX_POWER,CUSTOM_POWER_02',
      )
    end

    it 'initializes successfully' do
      expect(config).to be_a(described_class)
    end
  end

  describe 'Influx options' do
    let(:env) { valid_env }

    it 'matches the environment variables' do
      expect(config.influx_host).to eq(valid_env['INFLUX_HOST'])
      expect(config.influx_schema).to eq(valid_env['INFLUX_SCHEMA'])
      expect(config.influx_port).to eq(valid_env['INFLUX_PORT'])
      expect(config.influx_token).to eq(valid_env['INFLUX_TOKEN'])
      expect(config.influx_org).to eq(valid_env['INFLUX_ORG'])
      expect(config.influx_bucket).to eq(valid_env['INFLUX_BUCKET'])
      expect(config.influx_url).to eq('https://influx.example.com:443')
    end
  end

  describe 'Other options' do
    let(:env) { valid_env }

    it 'matches the environment variables' do
      expect(config.interval).to eq(600)
      expect(config.installation_date).to eq(Date.new(2021, 1, 1))
    end
  end

  describe 'invalid options' do
    context 'when all blank' do
      let(:env) { {} }

      it 'raises an exception' do
        expect { described_class.new(env) }.to raise_error(KeyError)
      end
    end

    context 'when invalid formatting' do
      let(:env) { valid_env.merge('INFLUX_SENSOR_GRID_IMPORT_POWER' => 'foo') }

      it 'raises an exception' do
        expect { described_class.new(env) }.to raise_error(
          Config::Error,
          /must be in format/,
        )
      end
    end

    context 'when no house_power' do
      let(:env) { valid_env.except('INFLUX_SENSOR_HOUSE_POWER') }

      it 'raises an exception' do
        expect { described_class.new(env) }.to raise_error(
          Config::Error,
          /must be set/,
        )
      end
    end

    context 'when no grid_import_power' do
      let(:env) { valid_env.except('INFLUX_SENSOR_GRID_IMPORT_POWER') }

      it 'raises an exception' do
        expect { described_class.new(env) }.to raise_error(
          Config::Error,
          /must be set/,
        )
      end
    end

    describe 'when exclusion list contains unknown sensor' do
      let(:env) do
        valid_env.merge(
          'INFLUX_SENSOR_CUSTOM_POWER_02' => 'm:f',
          'INFLUX_EXCLUDE_FROM_HOUSE_POWER' =>
            'HEATPUMP_POWER,WALLBOX_POWER,CUSTOM_POWER_10',
        )
      end

      it 'raises an exception' do
        expect { described_class.new(env) }.to raise_error(
          Config::Error,
          /Invalid sensor name/,
        )
      end
    end
  end
end
