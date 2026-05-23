# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class ManagersFlashCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [ "Date", "Rooms Sold", "Rooms Available", "Occupancy %", "Average Daily Rate (ADR)", "Revenue per Available Room (RevPAR)", "Room Revenue", "Tax", "Total Revenue" ]

          @report.rows.each do |row|
            csv << [
              row[:date].strftime("%Y-%m-%d"),
              row[:rooms_sold],
              row[:rooms_available],
              percentage(row[:occupancy_rate]),
              money(row[:adr]),
              money(row[:revpar]),
              money(row[:room_revenue]),
              money(row[:tax_amount]),
              money(row[:total_revenue])
            ]
          end

          csv << [
            "TOTAL",
            @report.totals[:rooms_sold],
            @report.totals[:rooms_available],
            percentage(@report.totals[:occupancy_rate]),
            money(@report.totals[:adr]),
            money(@report.totals[:revpar]),
            money(@report.totals[:room_revenue]),
            money(@report.totals[:tax_amount]),
            money(@report.totals[:total_revenue])
          ]
        end
      end

      private

      def percentage(value)
        format("%.2f%%", value.to_d * 100)
      end

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
