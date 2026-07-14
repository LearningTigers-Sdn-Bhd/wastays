# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class ArrivalsDeparturesPdfExportService
      def initialize(hotel:, report:, tab: "arrivals")
        @hotel = hotel
        @report = report
        @tab = tab.to_s
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 32, 32, 32, 32 ])

        draw_header(pdf)
        if @tab == "bibo"
          draw_bibo_sections(pdf)
        else
          draw_summary(pdf)
          draw_section(pdf, active_section_title, rows_for_active_tab, active_section_type, active_empty_message)
        end

        pdf.render
      end

      private

      def draw_header(pdf)
        logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
        if File.exist?(logo_path)
          pdf.image logo_path, at: [ pdf.bounds.right - 150, pdf.cursor + 8 ], width: 140
        else
          pdf.text_box "WAStays", at: [ pdf.bounds.right - 140, pdf.cursor + 8 ], width: 140, align: :right, size: 12, style: :bold
        end

        pdf.text "Guest Reports - #{active_tab_heading}", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold

        period_text = if @report.start_date == @report.end_date
          @report.start_date.strftime("%d %b %Y")
        else
          "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
        end
        pdf.text period_text, size: 10
        pdf.move_down 12
      end

      def draw_summary(pdf)
        card_gap = 12
        card_height = 62
        card_width = (pdf.bounds.width - card_gap) / 2.0
        top = pdf.cursor

        cards = [
          [ "Arrivals", @report.arrival_count.to_s ],
          [ "In-House", @report.in_house_count.to_s ],
          [ "Departures", @report.departure_count.to_s ],
          [ "Checkout", @report.checkout_count.to_s ]
        ]

        cards.each_with_index do |(label, value), index|
          row = index / 2
          column = index % 2
          x = column * (card_width + card_gap)
          y = top - (row * (card_height + card_gap))

          pdf.bounding_box([ x, y ], width: card_width, height: card_height) do
            pdf.stroke_color "D1D5DB"
            pdf.fill_color "FFFFFF"
            pdf.fill_and_stroke_rounded_rectangle([ 0, card_height ], card_width, card_height, 8)
            pdf.fill_color "000000"
            pdf.stroke_color "000000"

            pdf.bounding_box([ 10, card_height - 10 ], width: card_width - 20, height: card_height - 20) do
              pdf.text label, size: 9, style: :bold
              pdf.move_down 8
              pdf.text value, size: 14, style: :bold
            end
          end
        end

        pdf.move_cursor_to(top - ((card_height * 2) + card_gap + 10))
      end

      def draw_section(pdf, title, rows, type, empty_message)
        pdf.text title, size: 12, style: :bold
        pdf.move_down 6

        if rows.empty?
          pdf.text(empty_message, size: 10, style: :italic)
          pdf.move_down 14
          return
        end

        table_rows = rows.map do |row|
          status = type == :arrival ? "#{row[:pre_checkin_status]} / #{row[:guarantee_status]}" : row[:departure_status]
          if @tab == "in_house"
            boat_dep_str = if row[:boat_departure].present?
              boat_time = row[:boat_departure].in_time_zone(@hotel.hotel_time_zone)
              "#{boat_time.strftime('%d %b %Y')}\n#{boat_time.strftime('%I:%M %p')}"
            else
              "—"
            end
            [
              "#{row[:guest_name]}\n#{row[:confirmation_token]}",
              "#{row[:room_details]}\nRoom: #{row[:room_numbers]}",
              row[:stay_dates],
              status,
              boat_dep_str,
              row[:latest_note].presence || "-"
            ]
          else
            [
              "#{row[:guest_name]}\n#{row[:confirmation_token]}",
              "#{row[:room_details]}\nRoom: #{row[:room_numbers]}",
              row[:stay_dates],
              status,
              row[:latest_note].presence || "-"
            ]
          end
        end

        headers = if @tab == "in_house"
          [ "Guest / Ref", "Rooms", "Stay", "Departure", "Boat Departure", "Notes" ]
        else
          [ "Guest / Ref", "Rooms", "Stay", type == :arrival ? "Readiness" : "Departure", "Notes" ]
        end

        opts = { width: pdf.bounds.width, cell_style: { size: 9, padding: [ 6, 6, 6, 6 ] } }
        if @tab == "in_house"
          opts[:column_widths] = [
            pdf.bounds.width * 0.20,
            pdf.bounds.width * 0.18,
            pdf.bounds.width * 0.22,
            pdf.bounds.width * 0.11,
            pdf.bounds.width * 0.14,
            pdf.bounds.width * 0.15
          ]
        end

        pdf.table([ headers ] + table_rows, opts) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end

        pdf.move_down 14
      end

      def draw_bibo_sections(pdf)
        draw_bibo_section(pdf, "Boat Arrivals", @report.boat_ins, "No boat arrivals recorded or expected for this selected period.")
        pdf.move_down 20
        draw_bibo_section(pdf, "Boat Departures", @report.boat_outs, "No boat departures recorded or expected for this selected period.")
      end

      def draw_bibo_section(pdf, title, rows, empty_message)
        pdf.text title, size: 12, style: :bold
        pdf.move_down 6

        if rows.empty?
          pdf.text(empty_message, size: 10, style: :italic)
          pdf.move_down 14
          return
        end

        table_rows = rows.map do |row|
          [
            "#{row[:guest_name]}\n#{row[:confirmation_token]}",
            row[:room_type],
            row[:room_number],
            row[:stay_dates],
            row[:boat_time]
          ]
        end

        pdf.table([ [ "Guest / Ref", "Room Type", "Room", "Stay Dates", "Boat Time" ] ] + table_rows, width: pdf.bounds.width, cell_style: { size: 9, padding: [ 6, 6, 6, 6 ] }) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end
      end

      def rows_for_active_tab
        case @tab
        when "in_house" then @report.in_house
        when "departures" then @report.departures
        when "checkout" then @report.checkout
        else @report.arrivals
        end
      end

      def active_section_title
        {
          "arrivals" => "Expected Arrivals",
          "in_house" => "In-House Guests",
          "departures" => "Expected Departures",
          "checkout" => "Checkout Guests"
        }.fetch(@tab, "Expected Arrivals")
      end

      def active_tab_heading
        {
          "arrivals" => "Arrivals",
          "in_house" => "In-House",
          "departures" => "Departures",
          "checkout" => "Checkout",
          "bibo" => "Boat Transfers"
        }.fetch(@tab, "Arrivals")
      end

      def active_section_type
        @tab == "arrivals" ? :arrival : :departure
      end

      def active_empty_message
        {
          "arrivals" => "No arrivals scheduled for this selected period.",
          "in_house" => "No in-house guests for this selected period.",
          "departures" => "No departures scheduled for this selected period.",
          "checkout" => "No completed checkouts for this selected period."
        }.fetch(@tab, "No arrivals scheduled for this selected period.")
      end
    end
  end
end
