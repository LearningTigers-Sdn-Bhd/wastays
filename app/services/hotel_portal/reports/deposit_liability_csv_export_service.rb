# frozen_string_literal: true

module HotelPortal
  module Reports
    class DepositLiabilityCsvExportService
      def initialize(report:)
        @report = report
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << headers

          @report.rows.each do |row|
            csv << [
              @csv.text(row[:guest_name]), @csv.text(row[:confirmation_token]), @csv.text(row[:stay_dates]), @csv.text(row[:booking_status]),
              @csv.text(row[:room_details]), @csv.text(row[:folio_number]), @csv.money(row[:booking_payment_amount]), @csv.money(row[:earned_amount]),
              @csv.money(row[:refund_amount]), @csv.money(row[:remaining_liability]), @csv.date(row[:latest_deposit_posting_date])
            ]
          end

          csv << [ "TOTAL", nil, nil, nil, nil, nil, *@report.totals.values_at(:booking_payment_amount, :earned_amount, :refund_amount, :remaining_liability).map { |value| @csv.money(value) }, nil ]
        end
      end

      private

      def headers
        [ "Guest Name", "Booking Ref", "Stay", "Status", "Rooms", "Folio", "Booking Payment", "Earned", "Refunds", "Remaining Liability", "Latest Payment Date" ]
      end
    end
  end
end
