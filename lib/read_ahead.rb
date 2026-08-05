# Hands out the records of a day and starts reading the next one right away.
#
#   reader = ReadAhead.new(days) { |day| influx_pull.day_records(day) }
#   reader.records(day) # => what the block returned for that day
#   reader.cancel
#
# `records` returns what the block returns, for any day the caller asks for -
# but only a caller walking the range forwards ever finds a read already done.
class ReadAhead
  def initialize(days, &read)
    @days = days
    @read = read
    @pending = nil
  end

  # The next day is read while the caller is still busy with this one: the read
  # is InfluxDB's time and whatever the caller does with the records is its
  # own, so one after the other they add up and side by side only the longer
  # one counts.
  #
  # It starts once this day has arrived, not before, so that there is never
  # more than one query in flight - two of them would be back to competing for
  # the same machine, which is the thing being avoided here.
  def records(day)
    result = pending_for(day).value

    next_day = day.next_day
    @pending = ([next_day, start(next_day)] if @days.cover?(next_day))
    result
  end

  # Throws away what was read ahead rather than waiting for it: the caller is
  # giving up on the range, so nobody is going to ask for that day.
  def cancel
    @pending&.last&.kill
  end

  private

  # What was read ahead counts for that one day and no other. Handing it to a
  # caller that asked for a different day would answer with the records of the
  # day before it - silently, and as energy somebody is going to read.
  def pending_for(day)
    ahead_day, thread = @pending
    return thread if ahead_day == day

    thread&.kill
    start(day)
  end

  # A bare thread rather than a future from concurrent-ruby - which is what
  # would satisfy the cop below - because this read has to be possible to stop:
  # a restart must let go of a query that may otherwise sit in InfluxDB's read
  # timeout for minutes, and a future can only be dropped, which holds its pool
  # thread for just as long.
  #
  # A read that fails is raised again where its day was asked for, so Ruby
  # writing it to stderr on top of that would only report it twice.
  def start(day)
    thread = Thread.new { @read.call(day) } # rubocop:disable ThreadSafety/NewThread
    thread.report_on_exception = false
    thread
  end
end
