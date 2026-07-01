# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class ExtraChargePdfExportService
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
        pdf.text "Extra Charge Report", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold
        pdf.text "#{tab_label} · #{period_label}", size: 10
        pdf.move_down 12
      end

      def draw_summary(pdf)
        pdf.table(
          [
            [ "Tab", tab_label ],
            [ "Transactions", @report.totals[:transaction_count].to_s ],
            [ "Total Amount (MYR)", money(@report.totals[:total_amount]) ]
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
          pdf.text "No extra charge transactions found for this period.", size: 10, style: :italic
          return
        end

        detail_rows = @report.rows.map do |row|
          [
            row[:posting_date].strftime("%d %b %Y"),
            row[:booking_reference],
            row[:folio_number],
            row[:guest_name],
            row[:description],
            category_label(row[:category]),
            money(row[:amount])
          ]
        end

        pdf.table(
          [ [ "Posting Date", "Booking Ref", "Folio Ref", "Guest", "Description", "Category", "Amount (MYR)" ] ] +
          detail_rows +
          [ [ "TOTAL", nil, nil, nil, nil, @report.totals[:transaction_count].to_s, money(@report.totals[:total_amount]) ] ],
          width: pdf.bounds.width,
          cell_style: { size: 9, padding: [ 5, 6, 5, 6 ] }
        ) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
          row(-1).font_style = :bold
          row(-1).background_color = "F8FAFC"
        end
      end

      def tab_label
        @report.active_tab == "fb" ? "F&B" : "Non-F&B"
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

      def category_label(value)
        value.to_s.upcase
      end
    end
  end
end
