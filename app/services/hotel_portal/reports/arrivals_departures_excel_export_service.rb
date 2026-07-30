# frozen_string_literal: true

module HotelPortal
  module Reports
    class ArrivalsDeparturesExcelExportService
      def initialize(hotel:, report:, tab: "arrivals")
        @hotel = hotel
        @report = report
        @tab = tab.to_s
        @table = ArrivalsDeparturesCsvExportService.new(report: report, tab: tab)
      end

      def generate
        headers = @table.export_headers
        rows = @table.export_rows
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Guest Reports", period_label: period_label).generate do |builder|
          sheet = builder.add_sheet(name: sheet_name, widths: column_widths(headers), orientation: :landscape)
          builder.add_header(sheet: sheet, subtitle: sheet_name)
          builder.add_summary(sheet: sheet, metrics: [ [ "Records", data_record_count, nil ] ])
          builder.add_table(
            sheet: sheet, section_title: sheet_name, headers: headers, rows: rows,
            column_types: Array.new(headers.size, :text), total_row: nil,
            empty_message: "No guest records found for the selected period."
          )
        end
      end

      private

      # Guest names need the room; every other column holds a short date or time.
      def column_widths(headers)
        headers.map { |header| header == "Guest Name" ? 34 : 20 }
      end

      def data_record_count
        return @report.records.size if @tab == "meal_prep"

        @table.export_rows.size
      end

      def sheet_name
        return "Boat Transfers" if @tab == "bibo"
        return "Meal Prep" if @tab == "meal_prep"

        @tab.titleize
      end

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
    end
  end
end
