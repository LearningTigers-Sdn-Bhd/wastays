# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class SstCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [ "Invoice / Ref", "Guest Name", "Check-In", "Check-Out", "Taxable Amount (MYR)", "SST 8% (MYR)", "Total (MYR)" ]

          @report.rows.each do |row|
            csv << [
              row[:invoice_number],
              row[:guest_name],
              row[:check_in].strftime("%d %b %Y"),
              row[:check_out].strftime("%d %b %Y"),
              money(row[:taxable_amount]),
              money(row[:sst_amount]),
              money(row[:total_amount])
            ]
          end

          csv << [ "TOTAL", nil, nil, nil,
                   money(@report.totals[:taxable_amount]),
                   money(@report.totals[:sst_amount]),
                   money(@report.totals[:total_amount]) ]
        end
      end

      private

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
