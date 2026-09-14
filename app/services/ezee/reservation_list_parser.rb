# frozen_string_literal: true

require "roo"
require "roo-xls"

module Ezee
  # Reads an eZee "Reservation List" export into plain row structs.
  #
  # The export is Crystal Reports output: a banner, a 48-column grid of merged
  # cells, and summary blocks at the end. Roughly 69% of its rows are completely
  # blank, so the one rule that matters is stated in
  # docs/ezee-reservation-import.md and enforced here: read every row to the end,
  # classify each by content, and never stop on emptiness. "Read until the first
  # blank row" returns one row out of 1193 on the client's real file, without
  # raising.
  class ReservationListParser
    Result = Struct.new(:rows, :declared_total, :warnings, :error, keyword_init: true) do
      def success? = error.blank?
    end

    # One reservation. `remark` is the free-text line eZee prints underneath,
    # which staff use as a scratchpad -- it may say "cancel" on a row sitting
    # under the Active Reservation heading, so it is never read as a status.
    Row = Struct.new(
      :sheet_row, :reservation_number, :booked_at, :source, :guest_name,
      :arrival, :departure, :adults, :children, :nights, :room_number,
      :room_type, :rate_type, :total_amount, :amount_paid, :user, :remark,
      keyword_init: true
    )

    # Roo is 1-indexed; these are the merged-cell offsets the report writes to.
    COLUMNS = {
      reservation_number: 3, booked_at: 6, source: 11, guest_name: 17,
      arrival: 24, departure: 27, adults: 29, children: 32, nights: 34,
      room_number: 36, room_type: 38, rate_type: 39, total_amount: 41,
      amount_paid: 43, user: 47
    }.freeze

    HEADING_ROW = 14          # "Active Reservation"
    KNOWN_HEADINGS = [ "active reservation" ].freeze
    REMARK_OFFSET = 3         # a remark sits three rows under its reservation
    EXTENSIONS = { ".xls" => :xls, ".xlsx" => :xlsx, ".csv" => :csv }.freeze

    def self.call(...) = new(...).call

    def initialize(path:, filename: nil)
      @path = path.to_s
      @filename = (filename.presence || File.basename(@path)).to_s
    end

    def call
      extension = EXTENSIONS[File.extname(@filename).downcase]
      return failure("Unsupported file type. Upload a .xls, .xlsx or .csv export.") if extension.nil?

      sheet = Roo::Spreadsheet.open(@path, extension: extension)
      sheet.default_sheet = sheet.sheets.first
      extract(sheet)
    rescue Roo::Error, Ole::Storage::FormatError, ArgumentError, IOError => e
      failure("Could not read the file: #{e.message}")
    end

    private

    def extract(sheet)
      rows = []
      warnings = []
      last = sheet.last_row.to_i

      (1..last).each do |index|
        next unless data_row?(sheet, index)

        row = build_row(sheet, index)
        row.remark = remark_at(sheet, index + REMARK_OFFSET)
        rows << row
      end

      heading = cell(sheet, HEADING_ROW, 3)
      unless heading.blank? || KNOWN_HEADINGS.include?(heading.downcase)
        warnings << "Unrecognised group heading #{heading.inspect}. This importer " \
                    "only handles active reservations; re-export filtered to them."
      end

      declared = declared_total(sheet, last)
      if declared && declared != rows.size
        warnings << "The file states #{declared} reservations but #{rows.size} parsed. " \
                    "The layout may have changed -- check before importing."
      end

      return failure("No reservations found. Is this an eZee reservation list?") if rows.empty?

      Result.new(rows: rows, declared_total: declared, warnings: warnings)
    end

    # A data row is a reservation number plus an arrival. Group headings, remark
    # lines, the banner and every summary block fail one or both.
    def data_row?(sheet, index)
      cell(sheet, index, COLUMNS[:reservation_number]).match?(/\A\d{4,}\z/) &&
        cell(sheet, index, COLUMNS[:arrival]).present?
    end

    def build_row(sheet, index)
      Row.new(
        sheet_row: index,
        reservation_number: cell(sheet, index, COLUMNS[:reservation_number]),
        booked_at: parse_time(cell(sheet, index, COLUMNS[:booked_at])),
        source: cell(sheet, index, COLUMNS[:source]).sub(/\s*-\s*\z/, ""),
        guest_name: cell(sheet, index, COLUMNS[:guest_name]),
        arrival: parse_date(cell(sheet, index, COLUMNS[:arrival])),
        departure: parse_date(cell(sheet, index, COLUMNS[:departure])),
        adults: cell(sheet, index, COLUMNS[:adults]).to_i,
        children: cell(sheet, index, COLUMNS[:children]).to_i,
        nights: cell(sheet, index, COLUMNS[:nights]).to_i,
        room_number: cell(sheet, index, COLUMNS[:room_number]),
        room_type: cell(sheet, index, COLUMNS[:room_type]),
        rate_type: cell(sheet, index, COLUMNS[:rate_type]),
        total_amount: to_decimal(cell(sheet, index, COLUMNS[:total_amount])),
        amount_paid: to_decimal(cell(sheet, index, COLUMNS[:amount_paid])),
        user: cell(sheet, index, COLUMNS[:user])
      )
    end

    # A remark occupies its row alone, in the reservation-number column. One in
    # the client's file begins with a newline, so the value is squished rather
    # than assumed to be a single tidy line.
    def remark_at(sheet, index)
      return nil if index > sheet.last_row.to_i

      value = cell(sheet, index, COLUMNS[:reservation_number])
      return nil if value.blank? || value.match?(/\A\d{4,}\z/)
      return nil if KNOWN_HEADINGS.include?(value.downcase)
      return nil if other_columns_present?(sheet, index)

      value.squish.presence
    end

    def other_columns_present?(sheet, index)
      COLUMNS.except(:reservation_number).any? do |_name, column|
        cell(sheet, index, column).present?
      end
    end

    # The file states its own reservation count next to "Group Total :". It is
    # the cheapest guard against a layout change, so it is read back and compared.
    def declared_total(sheet, last)
      (1..last).reverse_each do |index|
        (1..4).each do |column|
          next unless cell(sheet, index, column).downcase.start_with?("group total")

          value = cell(sheet, index, 11)
          return value.to_i if value.match?(/\A\d+(\.0+)?\z/)
        end
      end
      nil
    end

    def cell(sheet, row, column)
      value = sheet.cell(row, column)
      case value
      when nil then ""
      when Float then value == value.to_i ? value.to_i.to_s : value.to_s
      else value.to_s.strip
      end
    end

    def parse_date(value)
      return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

      Date.parse(value.to_s[0, 9])
    rescue Date::Error
      nil
    end

    # eZee prints two-digit years ("02-Mar-26"). Time.zone.parse reads that as
    # year 26, not 2026, so the explicit format comes first and free-form
    # parsing is only the fallback for a re-saved file that carries real dates.
    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(DateTime)

      Time.zone.strptime(value.to_s, "%d-%b-%y %H:%M:%S")
    rescue ArgumentError
      begin
        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end

    def to_decimal(value)
      BigDecimal(value.to_s.delete(","))
    rescue ArgumentError, TypeError
      BigDecimal(0)
    end

    def failure(message) = Result.new(rows: [], warnings: [], error: message)
  end
end
