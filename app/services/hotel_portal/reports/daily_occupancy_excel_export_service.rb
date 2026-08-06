# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyOccupancyExcelExportService
      HEADERS = [ "Date", "Rooms Sold", "Rooms Available", "Occupancy %", "Room Revenue", "Average Daily Rate (ADR)", "Revenue per Available Room (RevPAR)", "Tax", "Total Revenue" ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Daily Occupancy Report", period_label: period_label).generate do |builder|
          sheet = builder.add_sheet(name: "Daily Occupancy", widths: [ 15, 13, 16, 14, 16, 22, 28, 14, 16 ], orientation: :landscape)
          builder.add_header(sheet: sheet)
          builder.add_summary(sheet: sheet, metrics: summary_metrics)
          builder.add_table(
            sheet: sheet, section_title: "Daily Occupancy", headers: HEADERS,
            rows: @report.rows.map { |row| [ row[:date], row[:rooms_sold], row[:rooms_available], row[:occupancy_rate], row[:room_revenue], row[:adr], row[:revpar], row[:tax_amount], row[:total_revenue] ] },
            column_types: %i[date integer integer percentage money money money money money],
            total_row: [ "TOTAL", @report.totals[:rooms_sold], @report.totals[:rooms_available], @report.totals[:occupancy_rate], @report.totals[:room_revenue], @report.totals[:adr], @report.totals[:revpar], @report.totals[:tax_amount], @report.totals[:total_revenue] ],
            empty_message: "No occupancy data for the selected period."
          )
        end
      end

      private

      def summary_metrics
        [
          [ "Rooms Sold", @report.totals[:rooms_sold], nil ], [ "Rooms Available", @report.totals[:rooms_available], nil ],
          [ "Room Revenue", @report.totals[:room_revenue], currency ], [ "Tax", @report.totals[:tax_amount], currency ],
          [ "Total Revenue", @report.totals[:total_revenue], currency ]
        ]
      end

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
