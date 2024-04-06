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
    }
  end

  let(:deprecated_env) do
    {
      'INFLUX_HOST' => 'influx.example.com',
      'INFLUX_SCHEMA' => 'https',
      'INFLUX_PORT' => '443',
      'INFLUX_TOKEN' => 'this.is.just.an.example',
      'INFLUX_ORG' => 'solectrus',
      'INFLUX_BUCKET' => 'my-bucket',
      'INFLUX_MEASUREMENT' => 'PV',
    }
  end

  describe 'valid options' do
    let(:env) { valid_env }

    it 'initializes successfully' do
      expect(config).to be_a(described_class)
    end
  end

  describe 'Influx methods' do
    let(:env) { valid_env }

    it 'matches the environment variables for Influx' do
      expect(config.influx_host).to eq(valid_env['INFLUX_HOST'])
      expect(config.influx_schema).to eq(valid_env['INFLUX_SCHEMA'])
      expect(config.influx_port).to eq(valid_env['INFLUX_PORT'])
      expect(config.influx_token).to eq(valid_env['INFLUX_TOKEN'])
      expect(config.influx_org).to eq(valid_env['INFLUX_ORG'])
      expect(config.influx_bucket).to eq(valid_env['INFLUX_BUCKET'])
      expect(config.influx_url).to eq('https://influx.example.com:443')
    end
  end

  describe 'invalid options' do
    context 'when all blank' do
      let(:env) { {} }

      it 'raises an exception' do
        expect { described_class.new(env) }.to raise_error(Exception)
      end
    end
  end
end
