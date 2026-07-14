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
          csv << [ "Date", "Bookings", "Accommodation", "Other Charges", "Tax", "Total Charges", "Discount", "Online", "Cash", "Deposit", "Agent Transfer", "Refund", "Net" ]

          @report.rows.each do |row|
            csv << [
              row[:date].strftime("%Y-%m-%d"),
              row[:booking_count],
              money(row[:accommodation]),
              money(row[:other_charges]),
              money(row[:tax]),
              money(row[:total_charges]),
              money(row[:discount]),
              money(row[:gateway_payment]),
              money(row[:cash_payment]),
              money(row[:booking_payment]),
              money(row[:ar_bank_transfer]),
              money(row[:refund]),
              money(row[:net_amount])
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
