# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class OutstandingBalanceCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [ "Guest Name", "Booking Ref", "Stay", "Rooms", "Room Numbers", "Payment Status", "Outstanding Amount", "Notes" ]

          @report.rows.each do |row|
            csv << [
              row[:guest_name],
              row[:confirmation_token],
              row[:stay_dates],
              row[:room_details],
              row[:room_numbers],
              row[:payment_status],
              money(row[:outstanding_amount]),
              row[:latest_note]
            ]
          end

          csv << [
            "TOTAL",
            nil,
            nil,
            nil,
            nil,
            nil,
            money(@report.totals[:outstanding_amount]),
            nil
          ]
        end
      end

      private

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
