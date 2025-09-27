require 'postgres_summaries'

describe PostgresSummaries do
  subject(:postgres_summaries) { described_class.new(config:) }

  let(:config) { Config.new(ENV.to_h, logger:) }
  let(:logger) { MemoryLogger.new }

  describe '#reset' do
    subject(:reset) { postgres_summaries.reset(since:) }

    let(:since) { Date.yesterday }

    context 'when PostgreSQL is available' do
      before do
        allow(config).to receive_messages(
          pg_host: 'localhost',
          pg_user: 'user',
          pg_password: 'password',
        )

        conn_double = instance_double(PG::Connection)
        allow(PG).to receive(:connect).and_return(conn_double)
        allow(conn_double).to receive(:exec).with(
          'DELETE FROM summaries WHERE date >= $1',
          [since],
        )
        allow(conn_double).to receive(:close)
      end

      it 'writes info message into log' do
        reset

        expect(logger.info_messages).to include(
          "Removed summaries since #{since}",
        )
      end
    end

    context 'when PostgreSQL is not available' do
      before do
        allow(config).to receive_messages(
          pg_host: 'localhost',
          pg_user: 'user',
          pg_password: 'password',
        )

        allow(PG).to receive(:connect).and_raise(
          PG::ConnectionBad.new('connection failed'),
        )
      end

      it 'writes error message into log' do
        reset

        expect(logger.error_messages).to include(
          /Failed to reset summaries table: connection failed/,
        )
      end
    end

    context 'when PostgreSQL ENV vars not set' do
      before do
        allow(config).to receive_messages(
          pg_host: nil,
          pg_user: nil,
          pg_password: nil,
        )
      end

      it 'writes warn message into log' do
        reset

        expect(logger.warn_messages).to include(
          'PostgreSQL ENV vars not set, skipping reset',
        )
      end
    end
  end
end
