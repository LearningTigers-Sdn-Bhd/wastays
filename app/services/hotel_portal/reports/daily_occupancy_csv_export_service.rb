# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class DailyOccupancyCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [ "Date", "Rooms Sold", "Rooms Available", "Occupancy %", "Room Revenue", "Average Daily Rate (ADR)", "Revenue per Available Room (RevPAR)" ]

          @report.rows.each do |row|
            csv << [
              row[:date].strftime("%Y-%m-%d"),
              row[:rooms_sold],
              row[:rooms_available],
              percentage(row[:occupancy_rate]),
              money(row[:room_revenue]),
              money(row[:adr]),
              money(row[:revpar])
            ]
          end

          csv << [
            "TOTAL",
            @report.totals[:rooms_sold],
            @report.totals[:rooms_available],
            percentage(@report.totals[:occupancy_rate]),
            money(@report.totals[:room_revenue]),
            money(@report.totals[:adr]),
            money(@report.totals[:revpar])
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
