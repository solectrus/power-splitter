#!/usr/bin/env ruby

require 'bundler/setup'
Bundler.require

$LOAD_PATH.unshift(File.expand_path('./lib', __dir__))

require 'time'
require 'dotenv/load'

# Core extensions are loaded once here, for the whole app
require 'active_support'
require 'active_support/core_ext'

require 'loop'
require 'config'
require 'stdout_logger'
require 'app_version'

logger = StdoutLogger.new

buildtime = ENV.fetch('BUILDTIME', nil).presence
buildtime = buildtime ? Time.parse(buildtime).localtime : '<unknown>'

logger.info 'Power Splitter for SOLECTRUS, ' \
              "Version #{AppVersion.current || '<unknown>'}, " \
              "built at #{buildtime}"
logger.info "Using #{RUBY_DESCRIPTION}"
logger.info 'Copyright (c) 2024-2026 Georg Ledermann <georg@ledermann.dev>'
logger.info 'https://github.com/solectrus/power-splitter'
logger.info "\n"

config = Config.new(ENV, logger:)

Loop.new(config:).start
