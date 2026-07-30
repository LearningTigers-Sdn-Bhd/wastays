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
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Guest Reports", period_label: period_label).generate do |builder|
          if @tab == "meal_prep"
            add_meal_prep_sheets(builder)
          else
            add_single_sheet(builder)
          end
        end
      end

      private

      def add_single_sheet(builder)
        headers = @table.export_headers
        sheet = builder.add_sheet(name: sheet_name, widths: column_widths(headers), orientation: :landscape)
        builder.add_header(sheet: sheet, subtitle: sheet_name)
        builder.add_summary(sheet: sheet, metrics: [ [ "Records", data_record_count, nil ] ])
        builder.add_table(
          sheet: sheet, section_title: sheet_name, headers: headers, rows: @table.export_rows,
          column_types: Array.new(headers.size, :text), total_row: nil,
          empty_message: "No guest records found for the selected period."
        )
      end

      # Every meal gets its own sheet, so the meal is the workspace rather than a
      # column. A single-meal tab yields a single sheet.
      def add_meal_prep_sheets(builder)
        headers = ArrivalsDeparturesCsvExportService::MEAL_PREP_COLUMNS

        @report.sections.each do |section|
          sheet = builder.add_sheet(name: section[:title], widths: column_widths(headers), orientation: :landscape)
          builder.add_header(sheet: sheet, subtitle: "Meal Prep - #{section[:title]}")
          builder.add_summary(sheet: sheet, metrics: [ [ "Transfers", section[:rows].size, nil ], [ "Total Pax", section[:total_pax], nil ] ])
          builder.add_table(
            sheet: sheet, section_title: section[:title], headers: headers,
            rows: section[:rows].map { |row| @table.meal_prep_row(row) },
            column_types: meal_prep_column_types,
            total_row: [ "Total Pax", section[:total_pax] ] + Array.new(headers.size - 2),
            empty_message: "No boat transfers or meal records found for the selected period."
          )
        end
      end

      def meal_prep_column_types
        ArrivalsDeparturesCsvExportService::MEAL_PREP_COLUMNS.map { |header| header == "Pax" ? :integer : :text }
      end

      # Guest names need the room; every other column holds a short date or time.
      def column_widths(headers)
        headers.map { |header| header == "Guest Name" ? 34 : 20 }
      end

      def data_record_count = @table.export_rows.size

      # Meal prep never lands here; it names its sheets after its meals.
      def sheet_name
        return "Boat Transfers" if @tab == "bibo"

        @tab.titleize
      end

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
    end
  end
end
