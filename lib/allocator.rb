# Distributes a pool of power among consumers.
#
# The wallbox is served first, the rest of the pool proportionally to each
# consumer's share of the total. No consumer ever gets more than it actually
# consumes. If the pool exceeds the total, the surplus stays undistributed -
# there is simply nobody left to give it to.
#
# `counted` names the consumers that actually draw from the pool. Custom
# sensors that are part of house power are not among them: they are a breakdown
# of house power, not an addition to it, and would otherwise be counted twice.
class Allocator
  def initialize(pool:, powers:, counted:, wallbox: nil)
    @pool = pool
    @powers = powers
    @counted = counted
    @wallbox = wallbox
  end

  attr_reader :pool, :powers, :counted, :wallbox

  def call
    @call ||=
      powers
        .transform_values { |power| share(power) }
        .merge(wallbox_power: wallbox_share)
  end

  # How much of the pool actually reached the consumers
  def allocated
    call.sum { |key, power| counted.include?(key) ? (power || 0) : 0 }
  end

  private

  def wallbox_share
    return @wallbox_share if defined?(@wallbox_share)

    @wallbox_share =
      if pool.nil? || wallbox.nil?
        nil
      elsif pool.positive? && wallbox.positive?
        [wallbox, pool].min
      else
        0
      end
  end

  def remaining
    @remaining ||= pool && wallbox_share ? pool - wallbox_share : pool
  end

  def total
    @total ||=
      powers.sum { |key, power| counted.include?(key) ? (power || 0) : 0 }
  end

  def share(power)
    return unless power && remaining
    return 0 unless total.positive?

    [remaining * power.fdiv(total), power].min
  end
end
