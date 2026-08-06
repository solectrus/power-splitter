require 'read_ahead'

describe ReadAhead do
  subject(:reader) { described_class.new(days) { |day| read(day) } }

  let(:days) { Date.new(2026, 6, 1)..Date.new(2026, 6, 3) }
  let(:reads) { Queue.new }

  def read(day)
    reads << day
    "records for #{day}"
  end

  describe '#answer' do
    it 'returns what the block returned' do
      expect(reader.answer(days.first)).to eq('records for 2026-06-01')
    end

    # Queue#pop blocks until the fetch ahead has actually run, so this says
    # the next day was fetched without waiting a fixed time for it.
    it 'fetches the next day without being asked' do
      reader.answer(days.first)

      expect(reads.pop).to eq(Date.new(2026, 6, 1))
      expect(reads.pop).to eq(Date.new(2026, 6, 2))
    end

    it 'hands out the day that was fetched ahead' do
      reader.answer(days.first)

      expect(reader.answer(days.first.next_day)).to eq('records for 2026-06-02')
      expect(reads.size).to eq(2)
    end

    # Nobody is going to ask for it, and on the historical run the day after
    # the range is one InfluxDB has no data for anyway.
    it 'stops at the end of the range' do
      days.each { |day| reader.answer(day) }

      expect(reads.size).to eq(days.count)
    end

    # The fetch ahead belongs to one day. Handing it out for another would
    # answer with the wrong day's records, and nothing downstream could tell.
    it 'fetches afresh when a day is skipped' do
      reader.answer(days.first)

      expect(reader.answer(days.first + 2)).to eq('records for 2026-06-03')
    end

    it 'lets a failed fetch fail where it was asked for' do
      reader = described_class.new(days) { raise IOError, 'InfluxDB is gone' }

      expect { reader.answer(days.first) }.to raise_error(
        IOError,
        'InfluxDB is gone',
      )
    end
  end

  describe '#cancel' do
    it 'does nothing when nothing was fetched' do
      expect { reader.cancel }.not_to raise_error
    end

    it 'gives up on the fetch ahead rather than waiting for it' do
      reader =
        described_class.new(days) do |day|
          sleep(30) unless day == days.first
          day
        end
      reader.answer(days.first)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      reader.cancel

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    end
  end
end
