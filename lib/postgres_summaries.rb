require 'pg'

class PostgresSummaries
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def reset
    unless config.pg_host && config.pg_user && config.pg_password &&
             config.pg_database
      config.logger.warn 'PostgreSQL ENV vars not set, skipping reset'
      return
    end

    conn =
      PG.connect(
        host: config.pg_host,
        user: config.pg_user,
        password: config.pg_password,
        dbname: config.pg_database,
      )

    begin
      conn.exec('DELETE FROM summaries')
      config.logger.info 'Summaries table reset successfully'
    ensure
      conn&.close
    end
  rescue StandardError => e
    config.logger.error "Failed to reset summaries table: #{e.message}"
  end
end
