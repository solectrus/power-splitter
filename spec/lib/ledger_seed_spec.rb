require 'ledger_seed'

describe LedgerSeed do
  subject(:seed) { described_class.new(day:, time:, balance: 123.4) }

  let(:day) { Date.new(2026, 6, 25) }
  let(:midnight) { Date.new(2026, 6, 26).beginning_of_day }

  # What a full day ends on: the last five-minute period before midnight
  let(:time) { midnight - 2.5.minutes }

  before { Time.zone = 'Europe/Berlin' }

  describe '#for' do
    it 'hands the balance to the day that follows' do
      expect(seed.for(day.next_day)).to eq(123.4)
    end

    # The ledger continues where the day before ended. A day in between that
    # was never written is a gap this knows nothing about.
    it 'says nothing about a later day' do
      expect(seed.for(day + 2)).to be_nil
    end

    it 'says nothing about the day it was left by' do
      expect(seed.for(day)).to be_nil
    end

    # Data that stopped hours before midnight says nothing about the night
    # that followed - the same window Flux::LastState searches.
    context 'when the day ended long before midnight' do
      let(:time) { midnight - Flux::Reader::MAX_AGE - 1.second }

      it 'says nothing' do
        expect(seed.for(day.next_day)).to be_nil
      end
    end

    context 'when the balance is exactly as old as the window allows' do
      let(:time) { midnight - Flux::Reader::MAX_AGE }

      it 'still hands it over' do
        expect(seed.for(day.next_day)).to eq(123.4)
      end
    end

    # A ledger that ran empty is a balance like any other, and must not be
    # mistaken for having none.
    context 'when the balance is zero' do
      subject(:seed) { described_class.new(day:, time:, balance: 0.0) }

      it 'hands over the zero' do
        expect(seed.for(day.next_day)).to eq(0.0)
      end
    end
  end
end
