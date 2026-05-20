# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class DepositLiabilityCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << headers

          @report.rows.each do |row|
            csv << [
              row[:guest_name],
              row[:confirmation_token],
              row[:stay_dates],
              row[:booking_status],
              row[:room_details],
              row[:folio_number],
              money(row[:advance_deposit_amount]),
              money(row[:earned_amount]),
              money(row[:refund_amount]),
              money(row[:remaining_liability]),
              row[:latest_deposit_posting_date]&.iso8601
            ]
          end

          csv << [ "TOTAL", nil, nil, nil, nil, nil, money(@report.totals[:advance_deposit_amount]), money(@report.totals[:earned_amount]), money(@report.totals[:refund_amount]), money(@report.totals[:remaining_liability]), nil ]
        end
      end

      private

      def headers
        [ "Guest Name", "Booking Ref", "Stay", "Status", "Rooms", "Folio", "Advance Deposit", "Earned", "Refunds", "Remaining Liability", "Latest Deposit Date" ]
      end

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
