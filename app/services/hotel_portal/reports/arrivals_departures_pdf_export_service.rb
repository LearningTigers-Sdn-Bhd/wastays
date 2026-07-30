# frozen_string_literal: true

module HotelPortal
  module Reports
    class ArrivalsDeparturesPdfExportService
      # Room, date and time share one width so both tables line up; the guest
      # name takes whatever page width is left over.
      BIBO_FIXED_COLUMN_WIDTH = 150

      # Same idea for meal prep, but its columns hold different amounts of text.
      MEAL_PREP_FIXED_COLUMN_WIDTHS = { "Pax" => 60, "Room Number" => 110, "Transfer" => 110,
                                        "Transfer Date" => 120, "Transfer Time" => 110 }.freeze

      def initialize(hotel:, report:, tab: "arrivals")
        @hotel = hotel
        @report = report
        @tab = tab.to_s
        @table = ArrivalsDeparturesCsvExportService.new(report: report, tab: tab)
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Guest Reports", subtitle: section_name, period_label: period_label, page_layout: :landscape)

        case @tab
        when "meal_prep" then add_meal_prep_pages(builder)
        when "bibo" then add_summary_and_header(builder) { add_bibo_tables(builder) }
        else add_summary_and_header(builder) { add_single_table(builder) }
        end

        builder.render
      end

      private

      def add_summary_and_header(builder)
        builder.add_header
        builder.add_summary([ [ "Records", record_count.to_s ] ])
        yield
      end

      def add_single_table(builder)
        headers = @table.export_headers
        builder.add_table(
          section_title: section_name, headers: headers,
          rows: @table.export_rows.reject(&:empty?).map { |row| row.map { |value| value.presence || "-" } },
          numeric_columns: [], total_row: nil,
          empty_message: "No guest records found for the selected period."
        )
      end

      # A kitchen works one meal at a time, so each meal gets its own printed page,
      # header and pax total.
      def add_meal_prep_pages(builder)
        headers = ArrivalsDeparturesCsvExportService::MEAL_PREP_COLUMNS
        widths = meal_prep_column_widths(builder, headers)
        pax_column = headers.index("Pax")

        @report.sections.each_with_index do |section, index|
          builder.start_new_page unless index.zero?
          builder.add_header
          builder.add_summary([ [ "Transfers", section[:rows].size.to_s ], [ "Total Pax", section[:total_pax].to_s ] ])
          builder.add_table(
            section_title: section[:title], headers: headers,
            rows: section[:rows].map { |row| @table.meal_prep_row(row).map { |value| value.blank? ? "-" : value.to_s } },
            numeric_columns: [ pax_column ],
            total_row: [ "Total Pax", section[:total_pax].to_s ] + Array.new(headers.size - 2),
            empty_message: "No boat transfers or meal records found for the selected period.",
            column_widths: widths
          )
        end
      end

      def meal_prep_column_widths(builder, headers)
        fixed = MEAL_PREP_FIXED_COLUMN_WIDTHS
        headers.map { |header| fixed.fetch(header, builder.content_width - fixed.values.sum) }
      end

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

      # Meal prep never lands here; each of its pages counts its own section.
      def record_count
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
