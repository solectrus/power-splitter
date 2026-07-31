# Keeps track of how much grid-sourced energy (in Wh) is currently stored in
# the home battery.
#
# Charging the battery while importing from the grid is a deposit, discharging
# it is a withdrawal. Grid energy is drawn first: as long as the balance is
# positive, energy leaving the battery is considered to originate from the grid.
#
# This guarantees that exactly as much grid energy leaves the battery as was
# put into it - no more, no less.
class BatteryLedger
  def initialize(balance = 0)
    @balance = [balance.to_f, 0.0].max
  end

  attr_reader :balance

  # Grid-sourced energy charged into the battery
  def deposit(energy)
    BatteryLedger.new(balance + positive(energy))
  end

  # Grid-sourced share of a discharge, without booking it. Used to determine
  # the origin of energy before it is known how much of it can be passed on.
  def offered(energy)
    [positive(energy), balance].min
  end

  # Book a withdrawal. Only pass in what actually reached the consumers -
  # anything else stays in the battery and is paid out later.
  def withdraw(energy)
    BatteryLedger.new(balance - offered(energy))
  end

  private

  def positive(energy)
    [energy.to_f, 0.0].max
  end
end
