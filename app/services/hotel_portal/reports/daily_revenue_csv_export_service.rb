# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class DailyRevenueCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [ "Date", "Bookings", "Room Revenue", "Tax", "Total Revenue" ]

          @report.rows.each do |row|
            csv << [
              row[:date].strftime("%Y-%m-%d"),
              row[:booking_count],
              money(row[:room_revenue]),
              money(row[:tax_amount]),
              money(row[:total_revenue])
            ]
          end
        end
      end

      private

      def money(value)
        format("MYR %.2f", value.to_d)
      end
    end
  end
end
