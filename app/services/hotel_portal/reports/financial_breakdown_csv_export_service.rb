# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialBreakdownCsvExportService
      HEADERS = [ "Booking Number", "Confirmation Code", "Guest Name", "Status", "Check In", "Check Out", "Gross", "Taxes", "Commission", "Net", "Currency" ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << HEADERS
          @report.currency_totals.each do |totals|
            rows_for(totals.fetch(:currency)).each { |row| csv << csv_row(row) }
            csv << total_row(totals)
          end
        end
      end

      private

      def csv_row(row)
        [
          @csv.text(row[:booking_number]), @csv.text(row[:confirmation_code]), @csv.text(row[:guest_name]),
          @csv.text(row[:status].to_s.titleize), @csv.date(row[:check_in]), @csv.date(row[:check_out]),
          @csv.money(row[:gross]), @csv.money(row[:taxes]),
          @csv.money(row[:margin]), @csv.money(row[:net]), @csv.text(row[:currency].presence || currency)
        ]
      end

      def total_row(totals)
        [
          "TOTAL", nil, nil, nil, nil, nil,
          *totals.values_at(:gross, :taxes, :margin, :net).map { |value| @csv.money(value) },
          @csv.text(totals.fetch(:currency))
        ]
      end

      def rows_for(currency_code)
        @report.rows.select { |row| row.fetch(:currency) == currency_code }
      end

      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
