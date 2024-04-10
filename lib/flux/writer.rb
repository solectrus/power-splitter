require_relative 'base'

module Flux
  class Writer < Flux::Base
    def push(records)
      write_api.write(data: records)
    end
  end
end
