# frozen_string_literal: true

module HotelPortal
  module Reports
    class OutstandingBalanceCsvExportService
      def initialize(report:)
        @report = report
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << [ "Guest Name", "Booking Ref", "Stay", "Rooms", "Room Numbers", "Payment Status", "Outstanding Amount", "Notes" ]

          @report.rows.each do |row|
            csv << [
              @csv.text(row[:guest_name]), @csv.text(row[:confirmation_token]), @csv.text(row[:stay_dates]),
              @csv.text(row[:room_details]), @csv.text(row[:room_numbers]), @csv.text(row[:payment_status]),
              @csv.money(row[:outstanding_amount]), @csv.text(row[:latest_note])
            ]
          end

          csv << [
            "TOTAL",
            nil,
            nil,
            nil,
            nil,
            nil,
            @csv.money(@report.totals[:outstanding_amount]),
            nil
          ]
        end
      end
    end
  end
end
