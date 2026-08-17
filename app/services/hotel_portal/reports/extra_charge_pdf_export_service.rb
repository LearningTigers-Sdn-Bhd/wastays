# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class ExtraChargePdfExportService
      THEME = Exports::PdfTheme
      COLORS = THEME::COLORS

      DETAIL_HEADERS = [
        "Posting Date", "Booking Ref", "Folio Ref", "Guest",
        "Description", "Category", "Currency", "Amount"
      ].freeze
      DESCRIPTION_CHUNK_SIZE = 500
      def initialize(hotel:, report:, prepared_by:)
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: THEME::PAGE_MARGIN)
        Exports::PdfTheme.configure_font(pdf)
        frame = Exports::PdfReportFrame.new(
          pdf: pdf,
          hotel: @hotel,
          report_name: "Extra Charge Report",
          subtitle: tab_label,
          period_label: period_label,
          prepared_by: @prepared_by
        )
        frame.draw_header
        draw_summary(pdf)
        draw_detail(pdf)
        frame.stamp_page_furniture
        pdf.render
      end

      private

      def draw_summary(pdf)
        Exports::PdfStatStrip.new(pdf: pdf).draw(
          [ [ "Transactions", transaction_count.to_s ], [ "Total Amount", amount_label(total_amount) ] ]
        )
      end

      def draw_detail(pdf)
        draw_section_heading(pdf, "Charge Details")
        if @report.rows.empty?
          draw_empty_state(pdf)
          pdf.move_down THEME::SPACE[:sm]
          draw_total_table(pdf)
          return
        end

        rows = @report.rows.flat_map { |row| detail_rows(row) }
        rows << total_row
        draw_detail_table(pdf, rows)
      end

      def draw_detail_table(pdf, rows)
        table = pdf.make_table(
          [ DETAIL_HEADERS ] + rows,
          header: true,
          width: pdf.bounds.width,
          column_widths: detail_column_widths(pdf),
          cell_style: {
            size: THEME::TYPE[:small],
            padding: THEME::TABLE_CELL_PADDING,
            border_color: COLORS[:border],
            borders: [ :bottom ],
            text_color: COLORS[:ink],
            valign: :top
          }
        )
        table.row(0).style(
          background_color: COLORS[:ink], text_color: COLORS[:white],
          font_style: :bold, size: THEME::TYPE[:small], borders: []
        )
        (rows.size - 1).times do |index|
          table.row(index + 1).background_color = COLORS[:stripe] if index.odd?
        end
        table.column(7).style(align: :right)
        table.row(rows.size).style(
          background_color: COLORS[:primary_light], font_style: :bold,
          borders: [ :top ], border_color: COLORS[:primary]
        )
        table.draw
      end

      def draw_total_table(pdf)
        table = pdf.make_table(
          [ total_row ],
          width: pdf.bounds.width,
          column_widths: detail_column_widths(pdf),
          cell_style: {
            size: THEME::TYPE[:small],
            padding: THEME::TABLE_CELL_PADDING,
            border_color: COLORS[:primary],
            borders: [ :top ],
            text_color: COLORS[:ink],
            background_color: COLORS[:primary_light],
            font_style: :bold
          }
        )
        table.column(7).style(align: :right)
        table.draw
      end

      def detail_rows(row)
        description_chunks(row[:description]).each_with_index.map do |description, index|
          if index.zero?
            [
              row[:posting_date].strftime("%d %b %Y"),
              row[:booking_reference],
              row[:folio_number],
              row[:guest_name],
              description,
              category_label(row[:category]),
              currency,
              amount_label(row[:amount])
            ]
          else
            [ nil, nil, nil, nil, description, nil, nil, nil ]
          end
        end
      end

      def description_chunks(description)
        chunks = description.to_s.scan(/\X/).each_slice(DESCRIPTION_CHUNK_SIZE).map(&:join)
        chunks.presence || [ "" ]
      end

      def total_row
        [ "Total", nil, nil, nil, nil, "#{transaction_count} #{'transaction'.pluralize(transaction_count)}", currency, amount_label(total_amount) ]
      end

      def detail_column_widths(pdf)
        fixed_widths = [ 75, 90, 75, 105, 160, 75, 60 ]
        fixed_widths + [ pdf.bounds.width - fixed_widths.sum ]
      end

      def draw_section_heading(pdf, title)
        pdf.fill_color COLORS[:ink]
        pdf.text title, size: THEME::TYPE[:heading], style: :bold
        pdf.move_down THEME::SPACE[:sm]
      end

      def draw_empty_state(pdf)
        pdf.fill_color COLORS[:muted]
        pdf.text "No extra charge transactions found for this period.", size: THEME::TYPE[:small], style: :italic
        pdf.fill_color COLORS[:ink]
      end

      def tab_label
        @report.active_tab == "fb" ? "F&B" : "Non-F&B"
      end

      def period_label
        return @report.start_date.strftime("%d %b %Y") if @report.start_date == @report.end_date

        "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      end

      def currency
        @hotel.default_currency.presence || "MYR"
      end

      def transaction_count
        @report.totals[:transaction_count]
      end

      def total_amount
        @report.totals[:total_amount]
      end

      def amount_label(value)
        "#{currency} #{money(value)}"
      end

      def money(value)
        format("%.2f", value.to_d)
      end

      def category_label(value)
        return "F&B" if value.to_s == "fb"

        value.to_s.humanize
      end
    end
  end
end
