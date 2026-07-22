# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialPerformanceCsvExportService
      HEADERS = [ "Date", "Bookings", "Currency", "Gross", "Margin", "Net" ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << HEADERS
          @report.rows.each do |row|
            csv << [
              @csv.date(row[:date]), row[:booking_count], @csv.text(currency),
              @csv.money(row[:gross]), @csv.money(row[:margin]), @csv.money(row[:net])
            ]
          end
          csv << [
            "TOTAL", @report.totals[:booking_count], @csv.text(currency),
            @csv.money(@report.totals[:gross]), @csv.money(@report.totals[:margin]), @csv.money(@report.totals[:net])
          ]
        end
      end

      private

      def currency
        @hotel.default_currency.presence || "MYR"
      end
    end
  end
end
