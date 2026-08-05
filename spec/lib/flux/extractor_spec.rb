require 'flux/extractor'
require 'config'

describe Flux::Extractor do
  subject(:extractor) { described_class.new(config:) }

  let(:config) { Config.new(ENV) }

  describe '#records', vcr: 'extractor' do
    subject(:day_records) { extractor.records(day) }

    let(:time) { day.in_time_zone(config.time_zone).change(hour: 9, min: 42) }

    # A value is only carried forward for MAX_AGE, so a sensor has to keep
    # reporting for the whole day to be covered by it - and already before it,
    # because the first minutes of a day are covered by what was measured on
    # the day before.
    let(:times) do
      hourly = (0..23).map { |hour| time.change(hour:) }

      [hourly.first - 1.hour, *hourly]
    end

    # One sensor is enough to describe the stream. That every configured one
    # comes back under its own key is what the "day is today" context below
    # covers, over a handful of minutes rather than a day of them.
    let(:sensors) { [{ name: 'SENEC', fields: { 'grid_power_plus' => 42 } }] }

    before do
      points =
        times.flat_map do |sensor_time|
          sensors.map do |sensor|
            InfluxDB2::Point.new(
              name: sensor[:name],
              time: sensor_time.to_i,
              fields: sensor[:fields],
            )
          end
        end

      flux_write(points)
    end

    after { flux_cleanup }

    context 'when day is in the past' do
      let(:day) { Date.yesterday }

      it 'returns transformed data' do
        expect(day_records).to be_an(Array).and all(be_a(Hash)).and all(
                      include('time', 'SENEC:grid_power_plus'),
                    )

        expect(day_records.length).to eq(1440) # 24 hours * 60 records per hour (1m intervals)
      end

      # The sensors here report once an hour, and still every minute comes
      # back - how often they report does not shape the stream, the minute
      # window does. Processor#gap? rests on this: as long as the records run
      # minute by minute, one that is missing can only mean the carry-forward
      # window was exceeded, and that is where the battery ledger gives up.
      it 'covers every minute, whatever the reporting interval' do
        distances = day_records.each_cons(2).map { |a, b| b['time'] - a['time'] }

        expect(distances).to all(eq(1.minute))
      end

      # The carry-forward does not start over at the day boundary: what was
      # measured shortly before midnight still describes the minutes after it.
      # The day of the recording is whichever one it was made on, so only the
      # time of day is compared here.
      it 'covers the first minutes with the value from the day before' do
        expect(day_records.first['time'].strftime('%H:%M')).to eq('00:01')
        expect(day_records.first['SENEC:grid_power_plus']).to eq(42)
      end
    end

    # A sensor that goes silent must not keep producing values forever, or a
    # gap in the data would be indistinguishable from a constant load.
    context 'when a sensor stops reporting',
            vcr: {
              cassette_name: 'extractor-with-gap',
              match_requests_on: %i[method uri flux_query],
            } do
      let(:day) { Date.new(2024, 8, 27) }
      let(:times) { [time] } # reports once, then goes silent

      def value_at(hour, minute)
        wanted = day.in_time_zone(config.time_zone).change(hour:, min: minute)

        day_records.find { |record| record['time'] == wanted }&.[](
          'SENEC:grid_power_plus',
        )
      end

      it 'carries the last value forward, but not beyond MAX_AGE' do
        expect(value_at(9, 43)).to eq(42)
        expect(value_at(11, 0)).to eq(42)

        expect(value_at(12, 0)).to be_nil
        expect(value_at(23, 59)).to be_nil
      end

      # Silence is counted across the day boundary as well. Otherwise a day
      # would always start with MAX_AGE worth of minutes that are present but
      # empty, and a gap running over midnight would be invisible to everything
      # that tells a gap by a missing minute.
      it 'skips the minutes before the sensor reports' do
        expect(day_records.first['time']).to eq(
          day.in_time_zone(config.time_zone).change(hour: 9, min: 43),
        )
      end
    end

    # Today ends at the last completed period rather than at midnight. Where in
    # the day that lands does not matter, so it is asked early on - a few
    # minutes prove the same cut-off as a few hundred, and every sensor is
    # written out over each of them.
    context 'when day is today',
            vcr: {
              cassette_name: 'extractor-today',
              match_requests_on: %i[method uri flux_query],
            } do
      let(:day) { Date.new(2024, 8, 28) }

      let(:sensors) do
        [
          {
            name: 'SENEC',
            fields: {
              'grid_power_plus' => 42,
              'house_power' => 42,
              'wallbox_charge_power' => 42,
            },
          },
          { name: 'Heatpump', fields: { 'power' => 42 } },
        ]
      end

      before { travel_to(day.in_time_zone(config.time_zone).change(min: 22)) }

      # Back to the real clock before the outer hook cleans up: the deletion
      # reaches up to Time.current, so a frozen one would leave everything
      # written after it behind - for the specs that follow to stumble over.
      after { travel_back }

      it 'returns every sensor, up to the last completed period' do
        expect(day_records).to be_an(Array).and all(be_a(Hash)).and all(
                      include(
                        'time',
                        'SENEC:grid_power_plus',
                        'SENEC:house_power',
                        'SENEC:wallbox_charge_power',
                        'Heatpump:power',
                      ),
                    )

        expect(day_records.length).to eq(20) # 00:01 until 00:20, in 1m intervals
      end
    end
  end

  # A measurement holds until the next one arrives, so a minute is the average
  # of the seconds each value covered, not of the samples that happened to fall
  # into it. Sensors reporting on change alone are what the carry-forward exists
  # for, and averaging their samples would weigh a value that stood for five
  # seconds like one that stood for the whole minute.
  describe '#records when a sensor reports irregularly',
           vcr: {
             cassette_name: 'extractor-irregular',
             match_requests_on: %i[method uri flux_query],
           } do
    subject(:day_records) { extractor.records(day) }

    let(:day) { Date.new(2024, 8, 27) }
    let(:noon) { day.in_time_zone(config.time_zone).change(hour: 12) }

    # 3000 W standing since the minute before, dropping to 0 W ten seconds
    # before the minute is over.
    before do
      points =
        { (noon - 1.minute) => 3000, noon => 3000, (noon + 50.seconds) => 0 }
      flux_write(
        points.map do |time, value|
          InfluxDB2::Point.new(
            name: 'SENEC',
            time: time.to_i,
            fields: {
              'grid_power_plus' => value,
            },
          )
        end,
      )
    end

    after { flux_cleanup }

    it 'weighs each value by the seconds it covered' do
      record = day_records.find { it['time'] == noon + 1.minute }

      # 3000 W for 50 of the 60 seconds, 0 W for the last 10. Averaging the two
      # samples instead would give half of that.
      expect(record['SENEC:grid_power_plus']).to eq(2500)
    end
  end

  # Each sensor comes back as its own table, and since gaps are dropped the
  # tables no longer span the same minutes. Assembled in table order, the
  # records would come out interleaved.
  describe '#records when the sensors cover different minutes' do
    subject(:day_records) { extractor.records(day) }

    let(:day) { Date.new(2024, 8, 27) }

    # Annotated CSV as InfluxDB returns it, with one table per sensor and both
    # yielded results one after the other - the values, and the minutes still
    # within reach of a reading.
    let(:csv) do
      [
        '#datatype,string,long,dateTime:RFC3339,string,string,double',
        '#group,false,false,false,true,true,false',
        '#default,values,,,,,',
        ',result,table,_time,_field,_measurement,_value',
        *rows_for('values', 42),
        '',
        '#datatype,string,long,dateTime:RFC3339,string,string',
        '#group,false,false,false,true,true',
        '#default,reach,,,,',
        ',result,table,_time,_field,_measurement',
        *rows_for('reach'),
      ].join("\r\n")
    end

    # One table per sensor: the first reports at 00:01, 00:02 and 00:05, the
    # second every minute up to 00:05.
    def rows_for(name, value = nil)
      {
        'bat_power_minus' => [1, 2, 5],
        'grid_power_plus' => [1, 2, 3, 4, 5],
      }.each_with_index.flat_map do |(field, minutes), table|
        minutes.map do |minute|
          time = "2024-08-26T22:0#{minute}:00Z"
          ",#{[name, table, time, field, 'SENEC', value].compact.join(',')}"
        end
      end
    end

    before do
      stub_request(:post, %r{/api/v2/query}).to_return(
        body: csv,
        headers: {
          'Content-Type' => 'application/csv',
        },
      )
    end

    it 'returns the records in chronological order' do
      expect(day_records.map { it['time'] }).to eq(
        (1..5).map { |minute| day.in_time_zone(config.time_zone) + minute.minutes },
      )
    end
  end
end
