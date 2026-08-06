# Hands out the answer for a day and starts fetching the next one right away.
#
#   reader = ReadAhead.new(days) { |day| influx_pull.fetch_day(day) }
#   reader.answer(day) # => what the block returned for that day
#   reader.cancel
#
# `answer` returns what the block returns, for any day the caller asks for -
# but only a caller walking the range forwards ever finds a fetch already done.
#
# Whatever the block does runs in a thread of its own, so it should wait rather
# than work: two threads of Ruby share one GVL and would only take turns.
class ReadAhead
  def initialize(days, &read)
    @days = days
    @read = read
    @pending = nil
  end

  # The next day is fetched while the caller is still busy with this one: the
  # fetch is InfluxDB's time and whatever the caller does with the answer is
  # its own, so one after the other they add up and side by side only the
  # longer one counts.
  #
  # It starts once this day has arrived, not before, so that there is never
  # more than one query in flight - two of them would be back to competing for
  # the same machine, which is the thing being avoided here.
  def answer(day)
    result = pending_for(day).value

    next_day = day.next_day
    @pending = ([next_day, start(next_day)] if @days.cover?(next_day))
    result
  end

  # Throws away what was fetched ahead rather than waiting for it: the caller
  # is giving up on the range, so nobody is going to ask for that day.
  def cancel
    @pending&.last&.kill
  end

  private

  # What was fetched ahead counts for that one day and no other. Handing it to
  # a caller that asked for a different day would answer with the records of
  # the day before it - silently, and as energy somebody is going to read.
  def pending_for(day)
    ahead_day, thread = @pending
    return thread if ahead_day == day

    thread&.kill
    start(day)
  end

  # A bare thread rather than a future from concurrent-ruby - which is what
  # would satisfy the cop below - because this fetch has to be possible to stop:
  # a restart must let go of a query that may otherwise sit in InfluxDB's read
  # timeout for minutes, and a future can only be dropped, which holds its pool
  # thread for just as long.
  #
  # A fetch that fails is raised again where its day was asked for, so Ruby
  # writing it to stderr on top of that would only report it twice.
  def start(day)
    thread = Thread.new { @read.call(day) } # rubocop:disable ThreadSafety/NewThread
    thread.report_on_exception = false
    thread
  end
end
