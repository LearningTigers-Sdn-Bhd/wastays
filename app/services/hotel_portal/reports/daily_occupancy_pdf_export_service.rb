# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyOccupancyPdfExportService
      def initialize(hotel:, report:, prepared_by:)
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Daily Occupancy Report", period_label: period_label, prepared_by: @prepared_by, page_layout: :landscape)
        builder.add_header
        builder.add_summary([
          [ "Rooms Sold", @report.totals[:rooms_sold].to_s ], [ "Rooms Available", @report.totals[:rooms_available].to_s ],
          [ "Occupancy", percentage(@report.totals[:occupancy_rate]) ], [ "Total Revenue", amount(@report.totals[:total_revenue]) ]
        ])
        builder.add_table(
          section_title: "Daily Occupancy", headers: DailyOccupancyExcelExportService::HEADERS,
          rows: @report.rows.map { |row| [ date(row[:date]), row[:rooms_sold].to_s, row[:rooms_available].to_s, percentage(row[:occupancy_rate]), money(row[:room_revenue]), money(row[:adr]), money(row[:revpar]), money(row[:tax_amount]), money(row[:total_revenue]) ] },
          numeric_columns: (1..8).to_a,
          total_row: [ "TOTAL", @report.totals[:rooms_sold].to_s, @report.totals[:rooms_available].to_s, percentage(@report.totals[:occupancy_rate]), money(@report.totals[:room_revenue]), money(@report.totals[:adr]), money(@report.totals[:revpar]), money(@report.totals[:tax_amount]), money(@report.totals[:total_revenue]) ],
          empty_message: "No occupancy data for the selected period."
        )
        builder.render
      end

      private

      def period_label = @report.start_date == @report.end_date ? date(@report.start_date) : "#{date(@report.start_date)} - #{date(@report.end_date)}"
      def percentage(value) = format("%.2f%%", value.to_d * 100)
      def amount(value) = "#{currency} #{money(value)}"
      def money(value) = Exports::PdfTheme.money(value)
      def date(value) = value.strftime("%d %b %Y")
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
