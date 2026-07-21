# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class DailyRevenueTransactionsCsvExportService
      HEADERS = [
        "Posting Date", "Posted At", "Service Name", "Transaction Code",
        "Booking Ref", "Folio Number", "Guest Name", "Room Number",
        "Room Type", "Relationship Status", "Base Amount", "Tax", "Total Amount", "Currency"
      ].freeze

      def initialize(rows:)
        @rows = rows
      end

      def generate
        "\xEF\xBB\xBF" + CSV.generate(headers: true) do |csv|
          csv << HEADERS
          @rows.each do |row|
            csv << [
              row.posting_date.iso8601,
              row.transaction_time.iso8601,
              row.service_name,
              row.transaction_code,
              row.booking_reference,
              row.folio_number,
              row.guest_name,
              row.room_number,
              row.room_type_name,
              row.relationship_status,
              format("%.2f", row.signed_amount),
              format("%.2f", row.tax_amount),
              format("%.2f", row.total_amount),
              row.currency
            ]
          end
        end
      end
    end
  end
end
