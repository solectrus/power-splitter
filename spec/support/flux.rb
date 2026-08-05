require 'config'
require 'flux/writer'
require 'flux/deleter'

def config
  @config ||= Config.new(ENV)
end

def flux_writer
  @flux_writer ||= Flux::Writer.new(config:)
end

def flux_deleter
  @flux_deleter ||= Flux::Deleter.new(config:)
end

def flux_write(data)
  # A single point is as valid an argument to the write API as a list of them
  written_measurements.concat(Array(data).map { measurement_of(it) })
  flux_writer.push(data)
end

# Removes what this example wrote, measurement by measurement. Wiping the
# bucket in one go would be shorter, but the bucket also holds the readings of
# every other SOLECTRUS component - so the project has no way to express that,
# and the specs get none either.
def flux_cleanup
  written_measurements.uniq.each { flux_deleter.delete_measurement(it) }
  written_measurements.clear
end

# The measurement is the first token of the line protocol. A Point does not
# expose it any other way.
def measurement_of(point)
  point.to_line_protocol[/\A[^,\s]+/]
end

# Per example: RSpec builds a fresh instance for each, so nothing carries over.
def written_measurements
  @written_measurements ||= []
end
