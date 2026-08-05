require 'read_ahead'

describe ReadAhead do
  subject(:reader) { described_class.new(days) { |day| read(day) } }

  let(:days) { Date.new(2026, 6, 1)..Date.new(2026, 6, 3) }
  let(:reads) { Queue.new }

  def read(day)
    reads << day
    "records for #{day}"
  end

  describe '#records' do
    it 'returns what the block returned' do
      expect(reader.records(days.first)).to eq('records for 2026-06-01')
    end

    # Queue#pop blocks until the read ahead has actually run, so this says the
    # next day was read without waiting a fixed time for it.
    it 'reads the next day without being asked' do
      reader.records(days.first)

      expect(reads.pop).to eq(Date.new(2026, 6, 1))
      expect(reads.pop).to eq(Date.new(2026, 6, 2))
    end

    it 'hands out the day that was read ahead' do
      reader.records(days.first)

      expect(reader.records(days.first.next_day)).to eq('records for 2026-06-02')
      expect(reads.size).to eq(2)
    end

    # Nobody is going to ask for it, and on the historical run the day after
    # the range is one InfluxDB has no data for anyway.
    it 'stops at the end of the range' do
      days.each { |day| reader.records(day) }

      expect(reads.size).to eq(days.count)
    end

    # The read ahead belongs to one day. Handing it out for another would
    # answer with the wrong day's records, and nothing downstream could tell.
    it 'reads afresh when a day is skipped' do
      reader.records(days.first)

      expect(reader.records(days.first + 2)).to eq('records for 2026-06-03')
    end

    it 'lets a failed read fail where it was asked for' do
      reader = described_class.new(days) { raise IOError, 'InfluxDB is gone' }

      expect { reader.records(days.first) }.to raise_error(
        IOError,
        'InfluxDB is gone',
      )
    end
  end

  describe '#cancel' do
    it 'does nothing when nothing was read' do
      expect { reader.cancel }.not_to raise_error
    end

    it 'gives up on the read ahead rather than waiting for it' do
      reader =
        described_class.new(days) do |day|
          sleep(30) unless day == days.first
          day
        end
      reader.records(days.first)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      reader.cancel

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    end
  end
end
