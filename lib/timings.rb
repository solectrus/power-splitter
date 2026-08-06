# Time spent in the phases of a run, in the order they were measured.
#
#   timings = Timings.new
#   timings.measure(:read) { influx_pull.fetch_day(day) }
#   timings.measure(:calc) { Processor.new(...).call }
#   timings.to_s # => "read 3.81s, calc 1.14s, total 4.95s"
#
# `measure` hands back whatever its block returned, so wrapping a call in it
# changes nothing but the bookkeeping.
class Timings
  def initialize
    @seconds = {}
  end

  # Booked in `ensure`, so a phase that raised is still accounted for - the one
  # that ran into a timeout is the one whose duration says the most.
  def measure(phase)
    started = monotonic_now
    yield
  ensure
    @seconds[phase] = monotonic_now - started
  end

  def to_s
    phases = @seconds.map { |phase, seconds| "#{phase} #{formatted(seconds)}" }

    [*phases, "total #{formatted(@seconds.values.sum(0.0))}"].join(', ')
  end

  private

  def formatted(seconds)
    "#{seconds.round(2)}s"
  end

  # The monotonic clock, so that a duration survives the system clock being
  # adjusted - which on a machine without a battery-backed RTC happens right
  # after boot, exactly when the first days are being processed.
  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
