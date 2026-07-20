# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class DailyRevenueTransactionsCsvExportService
      HEADERS = [
        "Posting Date", "Posted At", "Transaction Code", "Service Name",
        "Transaction Type", "Category", "Description", "Booking Ref",
        "Folio Number", "Guest Name", "Room Number", "Payment Method",
        "Posting Source", "Posted By", "Stay Date", "Relationship Status",
        "Related Transaction ID", "Amount", "Currency"
      ].freeze

      def initialize(transactions:)
        @transactions = transactions
      end

      def generate
        "\xEF\xBB\xBF" + CSV.generate(headers: true) do |csv|
          csv << HEADERS
          @transactions.each do |transaction|
            row = HotelPortal::Reports::DailyReportTransactionRow.new(transaction)
            csv << [
              row.posting_date.iso8601,
              row.posted_at&.iso8601,
              row.transaction_code,
              row.service_name,
              row.transaction_type,
              row.category,
              row.description,
              row.booking_reference,
              row.folio_number,
              row.guest_name,
              row.room_number,
              row.payment_method,
              row.posting_source,
              row.actor_name,
              row.stay_date,
              row.relationship_status,
              row.related_transaction_id,
              format("%.2f", row.signed_amount),
              row.currency
            ]
          end
        end
      end
    end
  end
end
