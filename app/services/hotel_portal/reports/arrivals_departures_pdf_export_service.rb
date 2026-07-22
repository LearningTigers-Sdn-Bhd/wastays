# frozen_string_literal: true

module HotelPortal
  module Reports
    class ArrivalsDeparturesPdfExportService
      def initialize(hotel:, report:, tab: "arrivals")
        @hotel = hotel
        @report = report
        @tab = tab.to_s
        @table = ArrivalsDeparturesCsvExportService.new(report: report, tab: tab)
      end

      def generate
        headers = @table.export_headers
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Guest Reports", subtitle: section_name, period_label: period_label, page_layout: :landscape)
        builder.add_header
        builder.add_summary([ [ "Records", record_count.to_s ] ])
        builder.add_table(
          section_title: section_name, headers: headers,
          rows: @table.export_rows.reject(&:empty?).map { |row| row.map { |value| value.presence || "-" } },
          numeric_columns: [], total_row: nil,
          empty_message: "No guest records found for the selected period."
        )
        builder.render
      end

      private

      def record_count
        return @report.records.size if @tab == "meal_prep"
        return @report.boat_ins.size + @report.boat_outs.size if @tab == "bibo"

        @table.export_rows.size
      end

      def section_name
        { "arrivals" => "Arrivals", "in_house" => "In-House", "departures" => "Departures", "checkout" => "Checkout", "bibo" => "Boat Transfers", "meal_prep" => "Meal Prep" }.fetch(@tab, "Arrivals")
      end

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
    end
  end
end
