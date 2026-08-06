require 'flux/reader'

# The ledger balance a finished day leaves behind, for the day that follows.
#
#   seed = LedgerSeed.new(day:, time:, balance:)
#   seed.for(day + 1) # => the balance, or nil
#
# Reading the balance back out of InfluxDB answers the same thing, and is what
# happens whenever this says nothing. Only a day whose predecessor was just
# written by the same run is spared that query.
class LedgerSeed
  def initialize(day:, time:, balance:)
    @day = day
    @time = time
    @balance = balance
  end

  # The balance `day` may start from, or nil when this one cannot say.
  #
  # Only the day right after the one it was left by. The ledger continues where
  # the day before ended, and a day in between that was never written is a gap
  # this knows nothing about.
  #
  # And only while the balance is still in reach: data that stopped hours
  # before midnight says nothing about the night that followed. That is the
  # same window Flux::LastState searches, so both give the same answer.
  def for(day)
    return unless day == @day.next_day
    return if @time < day.beginning_of_day - Flux::Reader::MAX_AGE

    @balance
  end
end
