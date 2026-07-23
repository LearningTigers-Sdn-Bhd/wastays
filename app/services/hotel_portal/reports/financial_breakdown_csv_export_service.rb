# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialBreakdownCsvExportService
      HEADERS = [ "Booking Reference", "Guest Name", "Status", "Check In", "Check Out", "Gross", "Taxes", "Margin", "Net", "Currency" ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << HEADERS
          @report.rows.each { |row| csv << csv_row(row) }
          csv << [ "TOTAL", nil, nil, nil, nil, *@report.totals.values_at(:gross, :taxes, :margin, :net).map { |value| @csv.money(value) }, currency ]
        end
      end

      private

      def csv_row(row)
        [
          @csv.text(row[:booking_reference]), @csv.text(row[:guest_name]), @csv.text(row[:status].to_s.titleize),
          @csv.date(row[:check_in]), @csv.date(row[:check_out]), @csv.money(row[:gross]), @csv.money(row[:taxes]),
          @csv.money(row[:margin]), @csv.money(row[:net]), @csv.text(row[:currency].presence || currency)
        ]
      end

      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
