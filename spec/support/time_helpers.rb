require 'active_support/testing/time_helpers'

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers

  # travel_to without a block holds until it is undone, and RSpec does not undo
  # it on its own - a frozen clock would otherwise leak into every example that
  # follows.
  config.after { travel_back }
end
