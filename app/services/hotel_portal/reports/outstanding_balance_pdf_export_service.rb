# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class OutstandingBalancePdfExportService
      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 32, 32, 32, 32 ])

        draw_header(pdf)
        draw_summary(pdf)
        draw_detail(pdf)

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

        pdf.text "Outstanding Balance Report", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold

        period = if @report.start_date == @report.end_date
          @report.start_date.strftime("%d %b %Y")
        else
          "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
        end

        pdf.text period, size: 10
        pdf.move_down 12
      end

      def draw_summary(pdf)
        rows = [
          [ "Outstanding Bookings", @report.totals[:booking_count].to_s ],
          [ "Outstanding Amount", money(@report.totals[:outstanding_amount]) ]
        ]

        pdf.table(rows, width: 280, cell_style: { borders: [ :bottom ], padding: [ 6, 8, 6, 8 ] }) do
          columns(0).font_style = :bold
          columns(1).align = :right
        end
        pdf.move_down 16
      end

      def draw_detail(pdf)
        pdf.text "Outstanding Bookings", size: 12, style: :bold
        pdf.move_down 6

        if @report.rows.empty?
          pdf.text "No outstanding bookings for this selected period.", size: 10, style: :italic
          return
        end

        detail_rows = @report.rows.map do |row|
          [
            "#{row[:guest_name]}\n#{row[:confirmation_token]}",
            row[:stay_dates],
            row[:payment_status],
            money(row[:outstanding_amount]),
            row[:latest_note].presence || "-"
          ]
        end

        pdf.table(
          [ [ "Guest / Ref", "Stay", "Payment Status", "Outstanding Amount", "Notes" ] ] + detail_rows,
          width: pdf.bounds.width,
          cell_style: { size: 9, padding: [ 6, 6, 6, 6 ] }
        ) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end
      end

      def money(value)
        format("MYR %.2f", value.to_d)
      end
    end
  end
end
