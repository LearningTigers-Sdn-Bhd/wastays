# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class RefundReportPdfExportService
      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 32, 32, 32, 32 ])

        draw_header(pdf)
        draw_summary(pdf)
        draw_table(pdf)

        pdf.render
      end

      private

      def draw_header(pdf)
        logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
        if File.exist?(logo_path)
          pdf.image logo_path, at: [ pdf.bounds.right - 150, pdf.cursor + 8 ], width: 140
        end

        pdf.text "Refund Report", size: 18, style: :bold
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
        cards = [
          [ "Refund Count", @report.totals[:refund_count].to_s ],
          [ "Total Refund", money(@report.totals[:total_amount]) ]
        ]

        card_gap = 10
        card_height = 62
        cards_per_row = 2
        card_width = (pdf.bounds.width - (card_gap * (cards_per_row - 1))) / cards_per_row.to_f
        top = pdf.cursor

        cards.each_with_index do |(label, value), index|
          row = index / cards_per_row
          col = index % cards_per_row
          x = col * (card_width + card_gap)
          y = top - (row * (card_height + card_gap))

          pdf.bounding_box([ x, y ], width: card_width, height: card_height) do
            pdf.stroke_color "D1D5DB"
            pdf.fill_color "FFFFFF"
            pdf.fill_and_stroke_rounded_rectangle([ 0, card_height ], card_width, card_height, 8)
            pdf.fill_color "000000"
            pdf.stroke_color "000000"

            pdf.bounding_box([ 10, card_height - 10 ], width: card_width - 20, height: card_height - 20) do
              pdf.text label, size: 8, style: :bold
              pdf.move_down 8
              pdf.text value, size: 12, style: :bold
            end
          end
        end

        total_rows = (cards.size / cards_per_row.to_f).ceil
        used_height = (total_rows * card_height) + ((total_rows - 1) * card_gap)
        pdf.move_cursor_to(top - (used_height + 10))
      end

      def draw_table(pdf)
        pdf.text "Refund Records", size: 12, style: :bold
        pdf.move_down 6

        if @report.rows.empty?
          pdf.text "No refund data for this selected period.", size: 10, style: :italic
          return
        end

        rows = @report.rows.map do |row|
          [
            row[:date].strftime("%d %b %Y"),
            row[:room].to_s,
            row[:guest_name],
            row[:booking_reference],
            row[:refund_method],
            row[:reference],
            row[:status],
            row[:reason].to_s.truncate(30),
            money(row[:refund_amount])
          ]
        end

        pdf.table([
          [ "Date", "Room", "Guest", "Booking", "Method", "Reference", "Status", "Reason", "Amount" ]
        ] + rows, width: pdf.bounds.width, cell_style: { size: 7, padding: [ 4, 4, 4, 4 ] }) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end
      end

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
