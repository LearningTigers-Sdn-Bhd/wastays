# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class ExtraChargeCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [ "Posting Date", "Booking Ref", "Folio Ref", "Guest Name", "Description", "Category", "Amount (MYR)" ]

          @report.rows.each do |row|
            csv << [
              row[:posting_date].strftime("%d %b %Y"),
              row[:booking_reference],
              row[:folio_number],
              row[:guest_name],
              row[:description],
              category_label(row[:category]),
              money(row[:amount])
            ]
          end

          csv << [ "TOTAL", nil, nil, nil, nil, @report.totals[:transaction_count], money(@report.totals[:total_amount]) ]
        end
      end

      private

      def money(value)
        format("%.2f", value.to_d)
      end

      def category_label(value)
        value.to_s.upcase
      end
    end
  end
end
