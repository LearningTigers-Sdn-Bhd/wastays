# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyOccupancyCsvExportService
      def initialize(report:)
        @report = report
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << [ "Date", "Rooms Sold", "Rooms Available", "Occupancy %", "Room Revenue", "Average Daily Rate (ADR)", "Revenue per Available Room (RevPAR)", "Tax", "Total Revenue" ]

          @report.rows.each do |row|
            csv << [
              @csv.date(row[:date]),
              row[:rooms_sold],
              row[:rooms_available],
              percentage(row[:occupancy_rate]),
              @csv.money(row[:room_revenue]),
              @csv.money(row[:adr]),
              @csv.money(row[:revpar]),
              @csv.money(row[:tax_amount]),
              @csv.money(row[:total_revenue])
            ]
          end

          csv << [
            "TOTAL",
            @report.totals[:rooms_sold],
            @report.totals[:rooms_available],
            percentage(@report.totals[:occupancy_rate]),
            @csv.money(@report.totals[:room_revenue]),
            @csv.money(@report.totals[:adr]),
            @csv.money(@report.totals[:revpar]),
            @csv.money(@report.totals[:tax_amount]),
            @csv.money(@report.totals[:total_revenue])
          ]
        end
      end

      private

      def percentage(value)
        format("%.2f%%", value.to_d * 100)
      end
    end
  end
end
