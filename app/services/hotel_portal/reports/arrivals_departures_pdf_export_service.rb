# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class ArrivalsDeparturesPdfExportService
      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 32, 32, 32, 32 ])

        draw_header(pdf)
        draw_summary(pdf)
        draw_section(pdf, "Expected Arrivals", @report.arrivals, :arrival)
        draw_section(pdf, "Expected Departures", @report.departures, :departure)

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

        pdf.text "Arrivals & Departures Report", size: 18, style: :bold
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
          [ "Departures", @report.departure_count.to_s ]
        ]

        cards.each_with_index do |(label, value), index|
          x = index * (card_width + card_gap)
          y = top

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

        pdf.move_cursor_to(top - (card_height + 10))
      end

      def draw_section(pdf, title, rows, type)
        pdf.text title, size: 12, style: :bold
        pdf.move_down 6

        if rows.empty?
          pdf.text(type == :arrival ? "No arrivals scheduled for this selected period." : "No departures scheduled for this selected period.", size: 10, style: :italic)
          pdf.move_down 14
          return
        end

        table_rows = rows.map do |row|
          status = type == :arrival ? "#{row[:pre_checkin_status]} / #{row[:guarantee_status]}" : row[:departure_status]
          [
            "#{row[:guest_name]}\n#{row[:confirmation_token]}",
            "#{row[:room_details]}\nRoom: #{row[:room_numbers]}",
            row[:stay_dates],
            status,
            row[:latest_note].presence || "-"
          ]
        end

        pdf.table([ [ "Guest / Ref", "Rooms", "Stay", type == :arrival ? "Readiness" : "Departure", "Notes" ] ] + table_rows, width: pdf.bounds.width, cell_style: { size: 9, padding: [ 6, 6, 6, 6 ] }) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end

        pdf.move_down 14
      end
    end
  end
end
