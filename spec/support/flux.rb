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
  flux_writer.push(data)
end

def flux_delete_all
  flux_deleter.delete_all
end
