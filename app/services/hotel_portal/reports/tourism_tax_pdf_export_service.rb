# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class TourismTaxPdfExportService
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
        pdf.text "Tourism Tax Report", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold
        pdf.text period_label, size: 10
        pdf.move_down 12
      end

      def draw_summary(pdf)
        pdf.table(
          [
            [ "Guests", @report.totals[:guest_count].to_s ],
            [ "Total Due (MYR)", money(@report.totals[:total_due]) ],
            [ "Total Collected (MYR)", money(@report.totals[:total_collected]) ]
          ],
          width: 260,
          cell_style: { size: 10, padding: [ 5, 6, 5, 6 ] }
        ) do
          column(0).font_style = :bold
          column(0).background_color = "F8FAFC"
        end
        pdf.move_down 12
      end

      def draw_detail(pdf)
        if @report.rows.empty?
          pdf.text "No tourism tax bookings found for this period.", size: 10, style: :italic
          return
        end

        rows = @report.rows.map do |row|
          [
            row[:guest_name],
            row[:guest_country],
            row[:booking_reference],
            row[:check_in].strftime("%d %b %Y"),
            row[:check_out].strftime("%d %b %Y"),
            row[:nights].to_s,
            money(row[:tax_due]),
            money(row[:tax_collected]),
            row[:collection_status]
          ]
        end

        pdf.table(
          [ [ "Guest Name", "Nationality", "Booking Ref", "Check In", "Check Out", "Nights", "Tax Due (MYR)", "Tax Collected (MYR)", "Collection Status" ] ] +
          rows +
          [ [ "TOTAL", nil, nil, nil, nil, @report.totals[:guest_count].to_s, money(@report.totals[:total_due]), money(@report.totals[:total_collected]), nil ] ],
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

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
