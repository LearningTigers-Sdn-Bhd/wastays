# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class RefundReportCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [ "Date", "Room", "Guest", "Booking Ref", "Refund Method", "Reference", "Status", "Reason", "Refund Amount" ]

          @report.rows.each do |row|
            csv << [
              row[:date].strftime("%Y-%m-%d"),
              row[:room],
              row[:guest_name],
              row[:booking_reference],
              row[:refund_method],
              row[:reference],
              row[:status],
              row[:reason],
              money(row[:refund_amount])
            ]
          end
        end
      end

      private

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
