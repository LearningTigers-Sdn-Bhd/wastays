# frozen_string_literal: true

module HotelPortal
  module Reports
    class RefundReportCsvExportService
      def initialize(report:)
        @report = report
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << [ "Date", "Room", "Guest", "Booking Ref", "Refund Method", "Reference", "Status", "Reason", "Refund Amount" ]

          @report.rows.each do |row|
            csv << [
              @csv.date(row[:date]), @csv.text(row[:room]), @csv.text(row[:guest_name]), @csv.text(row[:booking_reference]),
              @csv.text(row[:refund_method]), @csv.text(row[:reference]), @csv.text(row[:status]), @csv.text(row[:reason]), @csv.money(row[:refund_amount])
            ]
          end
          csv << [ "TOTAL", nil, nil, nil, nil, nil, nil, nil, @csv.money(@report.totals[:total_amount]) ]
        end
      end
    end
  end
end
