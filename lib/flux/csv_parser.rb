require 'csv'
require 'base64'

module Flux
  # Parses InfluxDB's annotated CSV into plain row hashes (column => value),
  # flattened across Flux tables - no consumer here needs the table grouping.
  #
  # This replaces InfluxDB2::FluxCsvParser, which builds a FluxTable/FluxColumn/
  # FluxRecord object graph and normalises every timestamp through
  # `Time.parse(v).to_datetime.rfc3339(9)` - a string the call sites then parse
  # again with `time_zone.parse`. Handing back the raw RFC3339 string skips both
  # the round-trip and the object graph. A day of minute records for eight
  # sensors (11,520 rows) went from 373 ms to 26 ms, against 64 ms for the
  # Processor that consumes them.
  class CsvParser
    ANNOTATION_DATATYPE = '#datatype'.freeze
    ANNOTATION_DEFAULT = '#default'.freeze
    private_constant :ANNOTATION_DATATYPE, :ANNOTATION_DEFAULT

    def self.call(body)
      new(body).call
    end

    def initialize(body)
      @body = body
      @rows = []
      @labels = nil
      @casters = nil
      @datatypes = nil
      @defaults = nil
      @error_block = false
    end

    def call
      @body.each_line { |line| parse_line(line.chomp) }

      @rows
    end

    private

    def parse_line(line)
      return if line.empty?
      return parse_annotation(line) if line.start_with?('#')

      fields = split(line)
      return parse_header(fields) if @labels.nil?

      raise_query_error(fields) if @error_block

      @rows << build_row(@labels, @casters, fields)
    end

    def parse_annotation(line)
      fields = split(line)

      case fields.first
      when ANNOTATION_DATATYPE
        @datatypes = fields
      when ANNOTATION_DEFAULT
        @defaults = fields
      end

      # Whatever follows the annotation block is a fresh header line
      @labels = nil
    end

    def parse_header(fields)
      @labels = fields
      # InfluxDB reports a failure that happens mid-stream as a table of its
      # own, after it has already answered with HTTP 200. Only the header
      # tells it apart from a result.
      @error_block = fields[1] == 'error' && fields[2] == 'reference'
      @casters = build_casters(fields, @datatypes, @defaults)
      nil
    end

    def raise_query_error(fields)
      reference = fields[2]
      raise InfluxDB2::FluxQueryError.new(
              fields[1],
              reference.to_s.empty? ? 0 : reference.to_i,
            )
    end

    # Column 0 carries the annotation name and is empty on header and data
    # lines, so every column index is shifted by one throughout.
    def build_row(labels, casters, fields)
      row = {}
      index = 1
      while index < labels.length
        row[labels[index]] = casters[index].call(fields[index])
        index += 1
      end
      row
    end

    # Flux only quotes a field when it contains a comma, quote or newline -
    # which sensor names and numeric values never do. So the fast path splits,
    # and only a line that actually contains a quote pays for a real CSV parse.
    def split(line)
      line.include?('"') ? CSV.parse_line(line) : line.split(',', -1)
    end

    STRING = ->(value) { value }
    INTEGER = lambda(&:to_i)
    BOOLEAN = ->(value) { value.casecmp('true').zero? }
    BASE64 = ->(value) { Base64.decode64(value) }
    DOUBLE =
      lambda do |value|
        case value
        when '+Inf'
          Float::INFINITY
        when '-Inf'
          -Float::INFINITY
        else
          value.to_f
        end
      end
    private_constant :STRING, :INTEGER, :BOOLEAN, :BASE64, :DOUBLE

    def build_casters(labels, datatypes, defaults)
      Array.new(labels.length) do |index|
        caster_for(datatypes&.[](index), defaults&.[](index))
      end
    end

    # An empty cell falls back to the column's `#default` annotation, and to nil
    # when there is none - which is how an empty aggregation window arrives.
    # Casting it instead would turn a window nothing was measured in into a
    # measured zero.
    def caster_for(datatype, default)
      cast = cast_function(datatype)
      default = nil if default.to_s.empty?

      if default
        ->(value) { cast.call(value.to_s.empty? ? default : value) }
      else
        ->(value) { value.to_s.empty? ? nil : cast.call(value) }
      end
    end

    # dateTime columns deliberately stay raw strings: every call site turns them
    # into a zoned Time itself, so parsing here would only be thrown away.
    def cast_function(datatype)
      case datatype
      when 'double'
        DOUBLE
      when 'long', 'unsignedLong', 'duration'
        INTEGER
      when 'boolean'
        BOOLEAN
      when 'base64Binary'
        BASE64
      else
        STRING
      end
    end
  end
end
