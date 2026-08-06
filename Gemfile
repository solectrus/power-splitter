# Gem versions must age 3 days before being resolvable, matching the
# cooldown declared for bundler in .github/dependabot.yml
source 'https://rubygems.org', cooldown: 3

# Loads environment variables from `.env`. (https://github.com/bkeepers/dotenv)
gem 'dotenv'

# Ruby library for InfluxDB 2. (https://github.com/influxdata/influxdb-client-ruby)
gem 'influxdb-client'

# CSV Reading and Writing (https://github.com/ruby/csv)
gem 'csv'

# Support for encoding and decoding binary data using a Base64 representation. (https://github.com/ruby/base64)
gem 'base64'

# A toolkit of support libraries and Ruby core extensions extracted from the Rails framework. (https://rubyonrails.org)
gem 'activesupport'

# ActiveSupport pulls minitest in for `active_support/testing`, which nothing
# here loads - but Bundler installs it either way. Minitest 6 depends on prism,
# and that lands in the runtime image as 10 MB of gem plus compiled extension
# for a parser no production code touches. Minitest 5 has no dependencies.
gem 'minitest', '~> 5.25', require: false

# Simple low-level client for Redis 6+ (https://github.com/redis-rb/redis-client)
gem 'redis-client'

# Pg is the Ruby interface to the PostgreSQL RDBMS (https://github.com/ged/ruby-pg)
gem 'pg'

group :development do
  # Guard gem for RSpec (https://github.com/guard/guard-rspec)
  gem 'guard-rspec', require: false

  # Pretty print Ruby objects with proper indentation and colors (https://github.com/amazing-print/amazing_print)
  gem 'amazing_print'
end

group :development, :test do
  # rspec-3.13.2 (https://rspec.info)
  gem 'rspec'

  # Rake is a Make-like program implemented in Ruby (https://github.com/ruby/rake)
  gem 'rake'

  # Automatic Ruby code style checking tool. (https://github.com/rubocop/rubocop)
  gem 'rubocop'

  # A RuboCop plugin for Rake (https://github.com/rubocop/rubocop-rake)
  gem 'rubocop-rake'

  # Automatic performance checking tool for Ruby code. (https://github.com/rubocop/rubocop-performance)
  gem 'rubocop-performance'

  # Thread-safety checks via static analysis (https://github.com/rubocop/rubocop-thread_safety)
  gem 'rubocop-thread_safety'

  # Code style checking for RSpec files (https://github.com/rubocop/rubocop-rspec)
  gem 'rubocop-rspec'

  # Record your test suite's HTTP interactions and replay them during future test runs for fast, deterministic, accurate tests. (https://benoittgt.github.io/vcr)
  gem 'vcr'

  # Library for stubbing HTTP requests in Ruby. (https://github.com/bblimke/webmock)
  gem 'webmock'

  # Code coverage for Ruby (https://github.com/simplecov-ruby/simplecov)
  gem 'simplecov'
end
