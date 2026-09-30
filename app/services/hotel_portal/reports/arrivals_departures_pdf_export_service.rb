# frozen_string_literal: true

module HotelPortal
  module Reports
    class ArrivalsDeparturesPdfExportService
      # Room, date and time columns share fixed widths in portrait mode; guest name takes the remainder.
      BIBO_FIXED_COLUMN_WIDTHS = [ 100, 110, 100 ].freeze

      # Same idea for meal prep, but its columns hold different amounts of text.
      MEAL_PREP_FIXED_COLUMN_WIDTHS = { "Pax" => 40, "Room Number" => 75, "Transfer" => 75,
                                        "Transfer Date" => 85, "Transfer Time" => 75 }.freeze

      def initialize(hotel:, report:, prepared_by:, tab: "arrivals")
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
        @tab = tab.to_s
        @table = ArrivalsDeparturesCsvExportService.new(report: report, tab: tab)
      end

      def generate
        layout = %w[bibo meal_prep].include?(@tab) ? :portrait : :landscape
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Guest Reports", subtitle: section_name, period_label: period_label, prepared_by: @prepared_by, page_layout: layout)

        case @tab
        when "meal_prep" then add_meal_prep_pages(builder)
        when "bibo" then add_header_and_content(builder) { add_bibo_tables(builder) }
        else add_header_and_content(builder) { add_single_table(builder) }
        end

        builder.render
      end

      private

      def add_header_and_content(builder)
        builder.add_header
        yield
      end

      def add_single_table(builder)
        headers = @table.export_headers
        builder.add_table(
          section_title: section_name, section_meta: count_label(record_count, "record"), headers: headers,
          rows: @table.export_rows.reject(&:empty?).map { |row| row.map { |value| value.presence || "-" } },
          numeric_columns: [], total_row: nil,
          empty_message: "No guest records found for the selected period."
        )
      end

      # A kitchen works one meal at a time, so each meal gets its own printed page
      # and pax total. The complete report frame belongs on the first page only.
      def add_meal_prep_pages(builder)
        headers = ArrivalsDeparturesCsvExportService::MEAL_PREP_COLUMNS
        widths = meal_prep_column_widths(builder, headers)
        pax_column = headers.index("Pax")

        @report.sections.each_with_index do |section, index|
          builder.start_new_page unless index.zero?
          builder.add_header if index.zero?
          builder.add_summary([ [ "Transfers", section[:rows].size.to_s ], [ "Total Pax", section[:total_pax].to_s ] ])

          total_row = Array.new(headers.size)
          total_row[0] = "Total Pax"
          total_row[pax_column] = section[:total_pax].to_s

          builder.add_table(
            section_title: section[:title], headers: headers,
            rows: section[:rows].map { |row| @table.meal_prep_row(row).map { |value| value.blank? ? "-" : value.to_s } },
            numeric_columns: [ pax_column ],
            total_row: total_row,
            empty_message: "No boat transfers or meal records found for the selected period.",
            column_widths: widths
          )
        end
      end

      def meal_prep_column_widths(builder, headers)
        fixed = MEAL_PREP_FIXED_COLUMN_WIDTHS
        headers.map { |header| fixed.fetch(header, builder.content_width - fixed.values.sum) }
      end

      # One table per direction shown, so the page mirrors the on-screen split.
      def add_bibo_tables(builder)
        widths = bibo_column_widths(builder)

        @report.sections.each do |leg|
          rows = leg[:rows]
          builder.add_table(
            section_title: leg[:title], section_meta: count_label(rows.size, "transfer"),
            headers: [ "Guest Name", "Room Number", leg[:date_header], leg[:time_header] ],
            rows: rows.map { |row| [ row[:guest_name], row[:room_number], row[leg[:date_key]], row[:boat_time] ].map { |value| value.presence || "-" } },
            numeric_columns: [], total_row: nil, empty_message: leg[:empty_message],
            column_widths: widths
          )
        end
      end

      def bibo_column_widths(builder)
        fixed = BIBO_FIXED_COLUMN_WIDTHS
        [ builder.content_width - fixed.sum ] + fixed
      end

      # Meal prep never lands here; each of its pages counts its own section.
      def record_count
        return @report.boat_ins.size + @report.boat_outs.size if @tab == "bibo"

        @table.export_rows.size
      end

      def count_label(count, noun) = "#{count} #{count == 1 ? noun : noun.pluralize}"

      def section_name
        { "arrivals" => "Arrivals", "in_house" => "In-House", "departures" => "Departures", "checkout" => "Checkout", "bibo" => "Boat Transfers", "meal_prep" => "Meal Prep" }.fetch(@tab, "Arrivals")
      end

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
    end
  end
end
