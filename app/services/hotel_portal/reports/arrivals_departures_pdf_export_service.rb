# frozen_string_literal: true

module HotelPortal
  module Reports
    class ArrivalsDeparturesPdfExportService
      # Room, date and time share one width so both tables line up; the guest
      # name takes whatever page width is left over.
      BIBO_FIXED_COLUMN_WIDTH = 150

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
        if @tab == "bibo"
          add_bibo_tables(builder)
        else
          builder.add_table(
            section_title: section_name, headers: headers,
            rows: @table.export_rows.reject(&:empty?).map { |row| row.map { |value| value.presence || "-" } },
            numeric_columns: [], total_row: nil,
            empty_message: "No guest records found for the selected period."
          )
        end
        builder.render
      end

      private

      # Boat transfers print as two tables so the page mirrors the on-screen split.
      def add_bibo_tables(builder)
        widths = bibo_column_widths(builder)

        BiboReport::LEGS.each do |leg|
          rows = @report.public_send(leg[:rows_key])
          builder.add_table(
            section_title: leg[:title],
            headers: [ "Guest Name", "Room Number", leg[:date_header], leg[:time_header] ],
            rows: rows.map { |row| [ row[:guest_name], row[:room_number], row[leg[:date_key]], row[:boat_time] ].map { |value| value.presence || "-" } },
            numeric_columns: [], total_row: nil, empty_message: leg[:empty_message],
            column_widths: widths
          )
        end
      end

      def bibo_column_widths(builder)
        fixed = Array.new(3, BIBO_FIXED_COLUMN_WIDTH)
        [ builder.content_width - fixed.sum ] + fixed
      end

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
