require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  sensitive_environment_variables = %w[
    INFLUX_HOST
    INFLUX_TOKEN
    INFLUX_ORG
    INFLUX_BUCKET
  ]
  sensitive_environment_variables.each do |key_name|
    config.filter_sensitive_data("<#{key_name}>") { ENV.fetch(key_name, nil) }
  end

  # Flux queries all go to the same URI and differ only in their body. Deletes
  # carry a current timestamp, so their body must not be matched on.
  config.register_request_matcher(:flux_query) do |request, other|
    if request.uri.include?('/api/v2/query')
      request.body == other.body
    else
      true
    end
  end

  # VCR=all records again - but delete the cassettes first. It records into the
  # file rather than over it, so whatever the code no longer asks for stays
  # behind, and the specs pass either way because VCR still finds a matching
  # interaction. Only counting them afterwards shows it.
  record_mode = ENV['VCR'] ? ENV['VCR'].to_sym : :once
  config.default_cassette_options = {
    record: record_mode,
    allow_playback_repeats: true,
  }
end
