require 'influx_pull'

# Tells whether the records in InfluxDB were calculated by a version of the
# splitter that predates the battery ledger, and says so in the log.
#
#   OutdatedRecords.new(config:).exist? # => true
#
# Such records were split by rules that no longer apply, and nothing ever
# revisits them: processing resumes at the last day written and only moves
# forward. Only throwing them away puts the loop back at the beginning, where
# it rebuilds them under the current rules.
#
# The ledger field is what the two versions are told apart by, so this only
# works where that field is written at all. Without battery tracking its
# absence says nothing, and acting on it would wipe the measurement on every
# start.
#
# Adding the battery sensors to an existing installation looks the same and is
# treated the same: what was calculated without them is outdated as well.
class OutdatedRecords
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def exist?
    return false unless config.battery_tracking?
    return false unless influx_pull.last_splitter_date
    return false if influx_pull.battery_ledger_written?

    config.logger.info "\n--- Existing records are missing the battery ledger, " \
                         'so they were calculated by an older version'
    true
  end

  private

  def influx_pull
    @influx_pull ||= InfluxPull.new(config:)
  end
end
