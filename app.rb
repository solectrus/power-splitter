#!/usr/bin/env ruby

require 'bundler/setup'
Bundler.require

$LOAD_PATH.unshift(File.expand_path('./lib', __dir__))

require 'time'
require 'dotenv/load'
require 'active_support'
require 'loop'
require 'config'
require 'stdout_logger'

logger = StdoutLogger.new

buildtime = ENV.fetch('BUILDTIME', nil).presence
buildtime = buildtime ? Time.parse(buildtime).localtime : '<unknown>'

logger.info 'Power Splitter for SOLECTRUS, ' \
              "Version #{ENV.fetch('VERSION', '<unknown>')}, " \
              "built at #{buildtime}"
logger.info "Using Ruby #{RUBY_VERSION} on platform #{RUBY_PLATFORM}"
logger.info 'Copyright (c) 2024-2025 Georg Ledermann <georg@ledermann.dev>'
logger.info 'https://github.com/solectrus/power-splitter'
logger.info "\n"

config = Config.new(ENV, logger:)

Loop.new(config:).start
