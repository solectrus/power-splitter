require 'flux/csv_parser'

describe Flux::CsvParser do
  subject(:rows) { described_class.call(body) }

  # InfluxDB separates lines with CRLF, which the parser has to shed along
  # with the LF - a stray CR would end up inside the last column of every row.
  def csv(*lines)
    "#{lines.join("\r\n")}\r\n"
  end

  context 'with a plain result table' do
    let(:body) do
      csv(
        '#datatype,string,long,dateTime:RFC3339,string,string,double',
        '#group,false,false,false,true,true,false',
        '#default,_result,,,,,',
        ',result,table,_time,_measurement,_field,_value',
        ',,0,2026-07-01T00:01:00Z,SENEC,house_power,412.5',
        ',,0,2026-07-01T00:02:00Z,SENEC,house_power,413.5',
      )
    end

    it 'returns one hash per row, keyed by column label' do
      expect(rows).to eq(
        [
          {
            'result' => '_result',
            'table' => 0,
            '_time' => '2026-07-01T00:01:00Z',
            '_measurement' => 'SENEC',
            '_field' => 'house_power',
            '_value' => 412.5,
          },
          {
            'result' => '_result',
            'table' => 0,
            '_time' => '2026-07-01T00:02:00Z',
            '_measurement' => 'SENEC',
            '_field' => 'house_power',
            '_value' => 413.5,
          },
        ],
      )
    end

    # The call sites turn the timestamp into a zoned Time themselves, so
    # parsing it here would only be thrown away.
    it 'leaves timestamps as raw strings' do
      expect(rows.first['_time']).to be_a(String)
    end

    it 'applies the #default annotation to empty cells' do
      expect(rows.first['result']).to eq('_result')
    end
  end

  # A query spanning several sensors returns a table per sensor, all sharing
  # one annotation block. Consumers regroup by time, not by table.
  context 'with several tables under one annotation block' do
    let(:body) do
      csv(
        '#datatype,string,long,string,double',
        '#group,false,false,true,false',
        '#default,_result,,,',
        ',result,table,_field,_value',
        ',,0,house_power,412.5',
        ',,1,grid_power_plus,88.0',
      )
    end

    it 'flattens them into one list' do
      expect(rows.map { it['table'] }).to eq([0, 1])
      expect(rows.map { it['_field'] }).to eq(%w[house_power grid_power_plus])
    end
  end

  # A schema change starts a fresh annotation block, and the header line that
  # follows it replaces the previous column labels rather than adding to them.
  context 'with a second annotation block' do
    let(:body) do
      csv(
        '#datatype,string,long,double',
        '#group,false,false,false',
        '#default,_result,,',
        ',result,table,_value',
        ',,0,412.5',
        '',
        '#datatype,string,long,string',
        '#group,false,false,false',
        '#default,_result,,',
        ',result,table,_name',
        ',,1,SENEC',
      )
    end

    it 'switches to the new columns' do
      expect(rows).to eq(
        [
          { 'result' => '_result', 'table' => 0, '_value' => 412.5 },
          { 'result' => '_result', 'table' => 1, '_name' => 'SENEC' },
        ],
      )
    end
  end

  describe 'casting' do
    let(:body) do
      csv(
        '#datatype,string,long,double,boolean,unsignedLong,duration,base64Binary,string',
        ',result,table,_double,_boolean,_ulong,_duration,_binary,_string',
        ',,0,412.5,true,7,60,aGVsbG8=,plain',
      )
    end

    it 'converts each column according to its datatype' do
      expect(rows.first).to eq(
        'result' => nil,
        'table' => 0,
        '_double' => 412.5,
        '_boolean' => true,
        '_ulong' => 7,
        '_duration' => 60,
        '_binary' => 'hello',
        '_string' => 'plain',
      )
    end
  end

  context 'with infinite values' do
    let(:body) do
      csv(
        '#datatype,string,long,double,double',
        ',result,table,_low,_high',
        ',,0,-Inf,+Inf',
      )
    end

    it 'maps them to Float::INFINITY' do
      expect(rows.first['_low']).to eq(-Float::INFINITY)
      expect(rows.first['_high']).to eq(Float::INFINITY)
    end
  end

  # An aggregation window that nothing was measured in comes back empty. Casting
  # it would turn it into a measured zero, which is a different statement.
  context 'with an empty cell and no #default' do
    let(:body) do
      csv(
        '#datatype,string,long,double,string',
        ',result,table,_value,_field',
        ',,0,,house_power',
      )
    end

    it 'returns nil rather than a zero' do
      expect(rows.first['_value']).to be_nil
    end
  end

  context 'with a false boolean' do
    let(:body) do
      csv(
        '#datatype,string,long,boolean',
        ',result,table,_value',
        ',,0,false',
      )
    end

    it 'returns false' do
      expect(rows.first['_value']).to be(false)
    end
  end

  # Flux only quotes a field when it has to, so the fast path splits on commas
  # and only these lines fall back to a real CSV parse.
  context 'with a quoted value containing a comma' do
    let(:body) do
      csv(
        '#datatype,string,long,string,double',
        ',result,table,_measurement,_value',
        ',,0,"Sensor, outdoor",412.5',
      )
    end

    it 'keeps the comma inside the value' do
      expect(rows.first['_measurement']).to eq('Sensor, outdoor')
      expect(rows.first['_value']).to eq(412.5)
    end
  end

  # A failure that happens after InfluxDB has already answered with HTTP 200
  # arrives as a table of its own. Silently returning it as a row would let a
  # broken query read as a day without data.
  context 'with an error response' do
    let(:body) do
      csv(
        '#datatype,string,string',
        ',error,reference',
        ',failed to evaluate query,897',
      )
    end

    it 'raises' do
      expect { rows }.to raise_error(
        InfluxDB2::FluxQueryError,
        'failed to evaluate query',
      ) { |error| expect(error.reference).to eq(897) }
    end
  end

  context 'with an error response without a reference' do
    let(:body) do
      csv('#datatype,string,string', ',error,reference', ',compilation failed,')
    end

    it 'raises with a zero reference' do
      expect { rows }.to raise_error(InfluxDB2::FluxQueryError) do |error|
        expect(error.reference).to eq(0)
      end
    end
  end

  context 'when the result is empty' do
    let(:body) { '' }

    it 'returns no rows' do
      expect(rows).to eq([])
    end
  end
end
