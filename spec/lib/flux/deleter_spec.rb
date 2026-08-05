require 'flux/deleter'
require 'config'

describe Flux::Deleter do
  subject(:deleter) { described_class.new(config:) }

  let(:config) { Config.new(ENV) }
  let(:delete_api) { instance_double(InfluxDB2::DeleteApi, delete: nil) }

  before do
    client = instance_double(InfluxDB2::Client, create_delete_api: delete_api)
    allow(InfluxDB2::Client).to receive(:new).and_return(client)
  end

  describe '#delete_measurement' do
    subject(:delete) { deleter.delete_measurement('power_splitter') }

    # The range only exists because InfluxDB requires one, so it must not
    # select anything: a period is written under the timestamp of its center,
    # for one, so the one being measured right now lies ahead of the present.
    # Left behind, it dates the data to today and a rebuild finds nothing to do.
    it 'spans every record there could be' do
      delete

      expect(delete_api).to have_received(:delete) do |start, stop, **|
        expect(start).to be < Time.utc(1971)
        expect(stop).to be > Time.current + 10.years
      end
    end
  end
end
