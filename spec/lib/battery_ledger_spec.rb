require 'battery_ledger'

describe BatteryLedger do
  describe '#initialize' do
    it 'defaults to an empty balance' do
      expect(described_class.new.balance).to eq(0)
    end

    it 'never starts negative' do
      expect(described_class.new(-100).balance).to eq(0)
    end

    it 'accepts nil' do
      expect(described_class.new(nil).balance).to eq(0)
    end
  end

  describe '#deposit' do
    it 'adds grid energy' do
      expect(described_class.new(100).deposit(50).balance).to eq(150)
    end

    it 'ignores negative amounts' do
      expect(described_class.new(100).deposit(-50).balance).to eq(100)
    end

    it 'returns a new instance' do
      ledger = described_class.new(100)

      expect { ledger.deposit(50) }.not_to change(ledger, :balance)
    end
  end

  describe '#offered' do
    subject(:ledger) { described_class.new(100) }

    it 'offers the full amount when the balance is sufficient' do
      expect(ledger.offered(40)).to eq(40)
    end

    it 'offers no more than the balance' do
      expect(ledger.offered(400)).to eq(100)
    end

    it 'offers nothing from an empty ledger' do
      expect(described_class.new.offered(40)).to eq(0)
    end

    it 'does not book anything' do
      expect { ledger.offered(40) }.not_to change(ledger, :balance)
    end
  end

  describe '#withdraw' do
    it 'debits the balance' do
      expect(described_class.new(100).withdraw(40).balance).to eq(60)
    end

    it 'never goes below zero' do
      expect(described_class.new(100).withdraw(400).balance).to eq(0)
    end

    it 'ignores negative amounts' do
      expect(described_class.new(100).withdraw(-40).balance).to eq(100)
    end
  end

  describe 'conservation' do
    it 'pays out exactly what was paid in' do
      ledger = described_class.new.deposit(30).deposit(70)

      paid_out = 0
      3.times do
        offered = ledger.offered(40)
        paid_out += offered
        ledger = ledger.withdraw(offered)
      end

      expect(paid_out).to eq(100)
      expect(ledger.balance).to eq(0)
    end
  end
end
