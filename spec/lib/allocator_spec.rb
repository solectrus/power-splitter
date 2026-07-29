require 'allocator'

describe Allocator do
  subject(:allocator) do
    described_class.new(pool:, powers:, counted: powers.keys, wallbox:)
  end

  let(:wallbox) { nil }
  let(:powers) { { house_power: 50, heatpump_power: 30, custom_power: 20 } }

  describe '#call' do
    context 'when the pool covers everything' do
      let(:pool) { 100 }

      it 'gives each consumer its full power' do
        expect(allocator.call).to include(house_power: 50, heatpump_power: 30)
      end
    end

    context 'when the pool covers half' do
      let(:pool) { 50 }

      it 'gives each consumer half of its power' do
        expect(allocator.call).to include(house_power: 25, heatpump_power: 15)
      end
    end

    context 'when the pool exceeds the total' do
      let(:pool) { 1000 }

      it 'never gives more than the consumer uses' do
        expect(allocator.call).to include(house_power: 50, heatpump_power: 30)
      end
    end

    context 'when nothing is consumed' do
      let(:pool) { 100 }
      let(:powers) { { house_power: 0 } }

      it 'gives nothing' do
        expect(allocator.call).to include(house_power: 0)
      end
    end

    context 'when a power is unknown' do
      let(:pool) { 100 }
      let(:powers) { { house_power: 50, heatpump_power: nil } }

      it 'returns nil for it' do
        expect(allocator.call).to include(heatpump_power: nil)
      end
    end

    context 'when the pool is unknown' do
      let(:pool) { nil }

      it 'returns nil for everyone' do
        expect(allocator.call.values).to all(be_nil)
      end
    end

    context 'when the pool is unknown and the wallbox is idle' do
      let(:pool) { nil }
      let(:wallbox) { 0 }

      it 'returns nil for the consumers' do
        expect(allocator.call).to include(house_power: nil)
      end
    end

    context 'with a wallbox' do
      let(:pool) { 60 }
      let(:wallbox) { 40 }

      it 'serves the wallbox first' do
        expect(allocator.call).to include(wallbox_power: 40)
      end

      it 'distributes the rest proportionally' do
        expect(allocator.call).to include(house_power: 10, heatpump_power: 6)
      end
    end

    context 'with a wallbox larger than the pool' do
      let(:pool) { 30 }
      let(:wallbox) { 40 }

      it 'gives the wallbox no more than the pool' do
        expect(allocator.call).to include(wallbox_power: 30)
      end

      it 'leaves nothing for the others' do
        expect(allocator.call).to include(house_power: 0, heatpump_power: 0)
      end
    end
  end

  describe '#allocated' do
    let(:pool) { 60 }

    # As long as `counted` is the sum of the consumers drawing from the pool,
    # either everybody is capped or nobody is - so the pool is never left
    # partially distributed while a consumer still has room.
    it 'hands out the whole pool' do
      expect(allocator.allocated).to eq(60)
    end

    context 'when the pool exceeds the total' do
      let(:pool) { 1000 }

      it 'hands out no more than the consumers use' do
        expect(allocator.allocated).to eq(100)
      end
    end

    context 'with consumers that are only a breakdown of others' do
      let(:powers) { { house_power: 100, washer_power: 40, fridge_power: 10 } }
      let(:allocator) do
        described_class.new(pool:, powers:, counted: [:house_power])
      end

      it 'does not count them twice' do
        expect(allocator.allocated).to eq(60)
      end

      it 'still reports their share' do
        expect(allocator.call).to include(washer_power: 24, fridge_power: 6)
      end
    end
  end
end
