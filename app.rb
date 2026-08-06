#!/usr/bin/env ruby

require 'bundler/setup'
Bundler.require

$LOAD_PATH.unshift(File.expand_path('./lib', __dir__))

require 'time'
require 'dotenv/load'

# Core extensions are loaded once here, for the whole app. Named one by one
# rather than as the whole `core_ext` umbrella: that one costs 116 extra files
# and 9 MB of RSS for the lifetime of the worker.
require 'active_support'
require 'active_support/core_ext/object/blank'
# Not for us, but for the InfluxDB client: it encodes the Flux query with
# `to_json`, and this is what escapes the pipe-forward as >. Dropping it
# would change every request body on the wire - and every cassette with it.
require 'active_support/core_ext/object/json'
require 'active_support/core_ext/string/conversions'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/date/calculations'
require 'active_support/core_ext/date/conversions'
require 'active_support/core_ext/time/calculations'
require 'active_support/core_ext/time/zones'
require 'active_support/core_ext/date/zones'

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
