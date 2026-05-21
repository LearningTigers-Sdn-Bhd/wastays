# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class DepositLiabilityPdfExportService
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

        pdf.text "Deposit Liability Report", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold
        pdf.text "As of #{@report.as_of_date.strftime('%d %b %Y')}", size: 10
        pdf.move_down 12
      end

      def draw_summary(pdf)
        cards = [
          [ "Bookings", @report.totals[:booking_count].to_s ],
          [ "Booking Payments", money(@report.totals[:booking_payment_amount]) ],
          [ "Earned", money(@report.totals[:earned_amount]) ],
          [ "Remaining Liability", money(@report.totals[:remaining_liability]) ]
        ]
        card_gap = 8
        card_width = (pdf.bounds.width - (card_gap * 3)) / 4.0
        card_height = 58
        top = pdf.cursor

        cards.each_with_index do |(label, value), index|
          x = index * (card_width + card_gap)

          pdf.bounding_box([ x, top ], width: card_width, height: card_height) do
            pdf.stroke_color "D1D5DB"
            pdf.fill_color "FFFFFF"
            pdf.fill_and_stroke_rounded_rectangle([ 0, card_height ], card_width, card_height, 8)
            pdf.fill_color "000000"
            pdf.bounding_box([ 8, card_height - 10 ], width: card_width - 16, height: card_height - 18) do
              pdf.text label, size: 8, style: :bold
              pdf.move_down 8
              pdf.text value, size: 11, style: :bold
            end
          end
        end

        pdf.move_cursor_to(top - (card_height + 10))
      end

      def draw_detail(pdf)
        pdf.text "Open Deposit Liabilities", size: 12, style: :bold
        pdf.move_down 6

        if @report.rows.empty?
          pdf.text "No deposit liabilities for this as-of date.", size: 10, style: :italic
          return
        end

        detail_rows = @report.rows.map do |row|
          [
            "#{row[:guest_name]}\n#{row[:confirmation_token]}",
            row[:stay_dates],
            row[:booking_status],
            row[:folio_number].to_s,
            money(row[:booking_payment_amount]),
            money(row[:earned_amount]),
            money(row[:remaining_liability])
          ]
        end

        pdf.table(
          [ [ "Guest / Ref", "Stay", "Status", "Folio", "Deposit", "Earned", "Liability" ] ] + detail_rows,
          width: pdf.bounds.width,
          cell_style: { size: 8, padding: [ 5, 5, 5, 5 ] }
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
