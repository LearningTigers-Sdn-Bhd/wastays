# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class ManagersFlashPdfExportService
      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 32, 32, 32, 32 ], page_layout: :landscape)

        draw_header(pdf)
        draw_summary(pdf)
        draw_daily_table(pdf)

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

        pdf.text "Manager Flash Report", size: 18, style: :bold
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
          [ "Rooms Sold", @report.totals[:rooms_sold].to_s ],
          [ "Rooms Available", @report.totals[:rooms_available].to_s ],
          [ "Occupancy %", percentage(@report.totals[:occupancy_rate]) ],
          [ "Average Daily Rate (ADR)", money(@report.totals[:adr]) ],
          [ "Revenue per Available Room (RevPAR)", money(@report.totals[:revpar]) ],
          [ "Total Revenue", money(@report.totals[:total_revenue]) ]
        ]

        card_gap = 10
        card_height = 62
        cards_per_row = 3
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

      def draw_daily_table(pdf)
        pdf.text "Daily Breakdown", size: 12, style: :bold
        pdf.move_down 6

        if @report.rows.empty?
          pdf.text "No report data for this selected period.", size: 10, style: :italic
          return
        end

        table_rows = @report.rows.map do |row|
          [
            row[:date].strftime("%d %b %Y"),
            row[:rooms_sold].to_s,
            row[:rooms_available].to_s,
            percentage(row[:occupancy_rate]),
            money(row[:adr]),
            money(row[:revpar]),
            money(row[:room_revenue]),
            money(row[:tax_amount]),
            money(row[:total_revenue])
          ]
        end

        pdf.table(
          [ [ "Date", "Sold", "Avail", "Occupancy %", "Average Daily Rate (ADR)", "Revenue per Available Room (RevPAR)", "Room Rev", "Tax", "Total Rev" ] ] + table_rows,
          width: pdf.bounds.width,
          cell_style: { size: 9, padding: [ 6, 6, 6, 6 ] }
        ) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end
      end

      def percentage(value)
        format("%.2f%%", value.to_d * 100)
      end

      def money(value)
        format("MYR %.2f", value.to_d)
      end
    end
  end
end
