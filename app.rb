#!/usr/bin/env ruby

require 'bundler/setup'
Bundler.require

$LOAD_PATH.unshift(File.expand_path('./lib', __dir__))

require 'dotenv/load'
require 'active_support'
require 'loop'
require 'config'
require 'stdout_logger'

logger = StdoutLogger.new

logger.info 'Power Splitter for SOLECTRUS, ' \
       "Version #{ENV.fetch('VERSION', '<unknown>')}, " \
       "built at #{ENV.fetch('BUILDTIME', '<unknown>')}"
logger.info 'https://github.com/solectrus/power-splitter'
logger.info 'Copyright (c) 2024 Georg Ledermann'
logger.info "\n"

logger.info "Using Ruby #{RUBY_VERSION} on platform #{RUBY_PLATFORM}"
config = Config.new(ENV, logger:)
logger.info "Accessing InfluxDB at #{config.influx_url}, " \
       "bucket #{config.influx_bucket}"
logger.info "\n"

Loop.new(config:).start
