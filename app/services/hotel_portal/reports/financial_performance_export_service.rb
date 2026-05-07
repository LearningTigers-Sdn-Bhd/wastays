# frozen_string_literal: true

require "csv"
require "cgi"
require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class FinancialPerformanceExportService
      def initialize(hotel:, start_date:, end_date:, total_gross:, total_margin:, total_net:, booking_count:, daily_data:)
        @hotel = hotel
        @start_date = start_date
        @end_date = end_date
        @total_gross = total_gross.to_d
        @total_margin = total_margin.to_d
        @total_net = total_net.to_d
        @booking_count = booking_count.to_i
        @daily_data = daily_data
      end

      def generate_csv
        CSV.generate(headers: true) do |csv|
          csv << [ "Date", "Bookings", "Gross", "Margin", "Net" ]
          @daily_data.each do |date, values|
            csv << [ date.strftime("%Y-%m-%d"), values[:booking_count], money(values[:gross]), money(values[:margin]), money(values[:net]) ]
          end
        end
      end

      def generate_xls
        <<~XML
          <?xml version="1.0"?>
          <?mso-application progid="Excel.Sheet"?>
          <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
            <Worksheet ss:Name="Summary"><Table>#{summary_rows}</Table></Worksheet>
            <Worksheet ss:Name="Daily Performance"><Table>#{daily_rows}</Table></Worksheet>
          </Workbook>
        XML
      end

      def generate_pdf
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 32, 32, 32, 32 ])
        draw_header(pdf)
        pdf.text "Financial Performance Report", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold
        pdf.text "#{@start_date.strftime('%d %b %Y')} - #{@end_date.strftime('%d %b %Y')}", size: 10
        pdf.move_down 12

        draw_summary_cards(pdf)

        pdf.move_down 14
        rows = [ [ "Date", "Bookings", "Gross", "Margin", "Net" ] ] + @daily_data.map do |date, values|
          [ date.strftime("%d %b %Y"), values[:booking_count].to_s, money(values[:gross]), money(values[:margin]), money(values[:net]) ]
        end
        pdf.table(rows, width: pdf.bounds.width, cell_style: { size: 9, padding: [ 6, 6, 6, 6 ] }) { row(0).font_style = :bold }
        pdf.render
      end

      private

      def summary_rows
        [
          row([ "Metric", "Value" ]),
          row([ "Gross Bookings", money(@total_gross) ]),
          row([ "Total Margin", money(@total_margin) ]),
          row([ "Net Earnings", money(@total_net) ]),
          row([ "Total Reservations", @booking_count ])
        ].join("\n")
      end

      def daily_rows
        rows = [ row([ "Date", "Bookings", "Gross", "Margin", "Net" ]) ]
        @daily_data.each do |date, values|
          rows << row([ date.strftime("%Y-%m-%d"), values[:booking_count], money(values[:gross]), money(values[:margin]), money(values[:net]) ])
        end
        rows.join("\n")
      end

      def row(values)
        "<Row>#{values.map { |v| %(<Cell><Data ss:Type=\"String\">#{CGI.escapeHTML(v.to_s)}</Data></Cell>) }.join}</Row>"
      end

      def money(value)
        format("%.2f", value.to_d)
      end

      def draw_header(pdf)
        logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
        if File.exist?(logo_path)
          pdf.image logo_path, at: [ pdf.bounds.right - 150, pdf.cursor + 8 ], width: 140
        end
      end

      def draw_summary_cards(pdf)
        card_gap = 12
        card_height = 62
        card_width = (pdf.bounds.width - card_gap) / 2.0
        top = pdf.cursor

        cards = [
          [ "Gross Bookings", money(@total_gross) ],
          [ "Total Margin", money(@total_margin) ],
          [ "Net Earnings", money(@total_net) ],
          [ "Total Reservations", @booking_count.to_s ]
        ]

        cards.each_with_index do |(label, value), index|
          row = index / 2
          col = index % 2
          x = col * (card_width + card_gap)
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

        pdf.move_cursor_to(top - ((card_height * 2) + card_gap + 8))
      end
    end
  end
end
