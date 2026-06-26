# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class SstPdfExportService
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
        logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
        if File.exist?(logo_path)
          pdf.image logo_path, at: [ pdf.bounds.right - 150, pdf.cursor + 8 ], width: 140
        else
          pdf.text_box "WAStays", at: [ pdf.bounds.right - 140, pdf.cursor + 8 ], width: 140, align: :right, size: 12, style: :bold
        end

        pdf.text "SST Financial Report", size: 18, style: :bold
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
        card_gap = 12
        card_height = 62
        card_width = (pdf.bounds.width - card_gap * 3) / 4.0
        top = pdf.cursor

        cards = [
          [ "Bookings", @report.totals[:booking_count].to_s ],
          [ "Taxable Amount", money(@report.totals[:taxable_amount]) ],
          [ "SST Collected (8%)", money(@report.totals[:sst_amount]) ],
          [ "Grand Total", money(@report.totals[:total_amount]) ]
        ]

        cards.each_with_index do |(label, value), index|
          x = index * (card_width + card_gap)

          pdf.bounding_box([ x, top ], width: card_width, height: card_height) do
            pdf.stroke_color "D1D5DB"
            pdf.fill_color "FFFFFF"
            pdf.fill_and_stroke_rounded_rectangle([ 0, card_height ], card_width, card_height, 8)
            pdf.fill_color "000000"
            pdf.stroke_color "000000"

            pdf.bounding_box([ 10, card_height - 10 ], width: card_width - 20, height: card_height - 20) do
              pdf.text label, size: 9, style: :bold
              pdf.move_down 8
              pdf.text value, size: 13, style: :bold
            end
          end
        end

        pdf.move_cursor_to(top - (card_height + 10))
      end

      def draw_detail(pdf)
        pdf.text "Transaction Detail", size: 12, style: :bold
        pdf.move_down 6

        if @report.rows.empty?
          pdf.text "No SST transactions found for this period.", size: 10, style: :italic
          return
        end

        detail_rows = @report.rows.map do |row|
          [
            row[:invoice_number],
            row[:guest_name],
            row[:check_in].strftime("%d %b %Y"),
            row[:check_out].strftime("%d %b %Y"),
            money(row[:taxable_amount]),
            money(row[:sst_amount]),
            money(row[:total_amount])
          ]
        end

        total_row = [ "TOTAL", nil, nil, nil,
                      money(@report.totals[:taxable_amount]),
                      money(@report.totals[:sst_amount]),
                      money(@report.totals[:total_amount]) ]

        pdf.table(
          [ [ "Invoice / Ref", "Guest", "Check-In", "Check-Out", "Taxable (MYR)", "SST 8% (MYR)", "Total (MYR)" ] ] +
          detail_rows + [ total_row ],
          width: pdf.bounds.width,
          cell_style: { size: 9, padding: [ 5, 6, 5, 6 ] }
        ) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
          row(-1).font_style = :bold
          row(-1).background_color = "F8FAFC"
        end
      end

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
