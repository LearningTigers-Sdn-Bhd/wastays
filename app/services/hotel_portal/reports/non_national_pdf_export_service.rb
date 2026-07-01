# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class NonNationalPdfExportService
      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: [ 32, 32, 32, 32 ])
        draw_header(pdf)
        draw_summary(pdf)
        draw_detail(pdf)
        pdf.render
      end

      private

      def draw_header(pdf)
        pdf.text "Non-National Report", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold
        pdf.text period_label, size: 10
        pdf.move_down 12
      end

      def draw_summary(pdf)
        pdf.table(
          [
            [ "Guests", @report.totals[:guest_count].to_s ],
            [ "Nights", @report.totals[:nights].to_s ]
          ],
          width: 220,
          cell_style: { size: 10, padding: [ 5, 6, 5, 6 ] }
        ) do
          column(0).font_style = :bold
          column(0).background_color = "F8FAFC"
        end
        pdf.move_down 12
      end

      def draw_detail(pdf)
        if @report.rows.empty?
          pdf.text "No in-house non-national guests found for this period.", size: 10, style: :italic
          return
        end

        rows = @report.rows.map do |row|
          [
            row[:guest_name],
            row[:guest_country],
            row[:guest_home_address],
            row[:check_in].strftime("%d %b %Y"),
            row[:checked_in_at]&.strftime("%I:%M %p"),
            row[:check_out].strftime("%d %b %Y")
          ]
        end

        pdf.table(
          [ [ "Full Name", "Nationality", "Home Address", "Check In Date", "Check In Time", "Check Out Date" ] ] +
          rows +
          [ [ "TOTAL", nil, nil, nil, nil, nil ] ],
          width: pdf.bounds.width,
          cell_style: { size: 9, padding: [ 5, 6, 5, 6 ] }
        ) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
          row(-1).font_style = :bold
          row(-1).background_color = "F8FAFC"
        end
      end

      def period_label
        if @report.start_date == @report.end_date
          @report.start_date.strftime("%d %b %Y")
        else
          "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
        end
      end
    end
  end
end
