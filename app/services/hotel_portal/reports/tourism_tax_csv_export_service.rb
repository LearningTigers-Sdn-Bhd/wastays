# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class TourismTaxCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [ "Guest Name", "Nationality", "Booking Ref", "Check In", "Check Out", "Nights", "Tax Due (MYR)", "Tax Collected (MYR)", "Collection Status" ]

          @report.rows.each do |row|
            csv << [
              row[:guest_name],
              row[:guest_country],
              row[:booking_reference],
              row[:check_in].strftime("%d %b %Y"),
              row[:check_out].strftime("%d %b %Y"),
              row[:nights],
              money(row[:tax_due]),
              money(row[:tax_collected]),
              row[:collection_status]
            ]
          end

          csv << [ "TOTAL", nil, nil, nil, nil, @report.totals[:guest_count], money(@report.totals[:total_due]), money(@report.totals[:total_collected]), nil ]
        end
      end

      private

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
