# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class ExtraChargePdfExportService
      COLORS = {
        ink: "18332F",
        primary: "205B4E",
        primary_light: "E7F1ED",
        muted: "667772",
        border: "D9E4DF",
        stripe: "F5F8F7",
        white: "FFFFFF"
      }.freeze

      DETAIL_HEADERS = [
        "Posting Date", "Booking Ref", "Folio Ref", "Guest",
        "Description", "Category", "Currency", "Amount"
      ].freeze
      DESCRIPTION_CHUNK_SIZE = 500
      UNICODE_FONT_FAMILY = "WAStays Unicode"
      UNICODE_FONT_CANDIDATES = [
        {
          normal: "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
          bold: "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
        },
        {
          normal: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
          bold: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
        }
      ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: [ 40, 32, 42, 32 ])
        configure_unicode_font(pdf)
        draw_header(pdf)
        draw_summary(pdf)
        draw_detail(pdf)
        draw_footer(pdf)
        pdf.render
      end

      private

      def draw_header(pdf)
        top = pdf.cursor
        pdf.fill_color COLORS[:primary]
        pdf.fill_rectangle([ 0, top ], pdf.bounds.width, 58)
        pdf.fill_color COLORS[:white]
        pdf.text_box "EXTRA CHARGE REPORT", at: [ 16, top - 14 ], width: 250, height: 20, size: 16, style: :bold
        pdf.text_box tab_label, at: [ 16, top - 36 ], width: 250, height: 16, size: 9

        logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
        pdf.image logo_path, at: [ pdf.bounds.right - 145, top - 10 ], width: 125 if File.exist?(logo_path)

        pdf.move_down 70
        pdf.fill_color COLORS[:ink]
        pdf.text @hotel.name.to_s, size: 12, style: :bold
        pdf.move_down 2
        pdf.fill_color COLORS[:muted]
        pdf.text "Reporting period: #{period_label}", size: 9
        pdf.text "Generated: #{Time.current.strftime('%d %b %Y, %H:%M %Z')}", size: 8
        pdf.fill_color COLORS[:ink]
        pdf.move_down 14
      end

      def draw_summary(pdf)
        table = pdf.make_table(
          [ [ "Transactions", "Total Amount" ], [ transaction_count.to_s, amount_label(total_amount) ] ],
          width: pdf.bounds.width,
          cell_style: { padding: [ 8, 9 ], border_color: COLORS[:border] }
        )
        table.row(0).style(
          background_color: COLORS[:primary_light], text_color: COLORS[:muted],
          size: 8, font_style: :bold, borders: [ :bottom ]
        )
        table.row(1).style(text_color: COLORS[:ink], size: 12, font_style: :bold, borders: [])
        table.column(1).style(align: :right)
        table.draw
        pdf.move_down 16
      end

      def draw_detail(pdf)
        draw_section_heading(pdf, "Charge Details")
        if @report.rows.empty?
          draw_empty_state(pdf)
          pdf.move_down 10
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
            size: 8.5,
            padding: [ 5, 6 ],
            border_color: COLORS[:border],
            borders: [ :bottom ],
            text_color: COLORS[:ink],
            valign: :top
          }
        )
        table.row(0).style(
          background_color: COLORS[:ink], text_color: COLORS[:white],
          font_style: :bold, size: 8, borders: []
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
            size: 8.5,
            padding: [ 5, 6 ],
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
        pdf.text title, size: 11, style: :bold
        pdf.move_down 6
      end

      def draw_empty_state(pdf)
        pdf.fill_color COLORS[:muted]
        pdf.text "No extra charge transactions found for this period.", size: 9, style: :italic
        pdf.fill_color COLORS[:ink]
      end

      def draw_footer(pdf)
        pdf.number_pages "Page <page> of <total>",
          at: [ 0, -8 ], width: pdf.bounds.width, align: :center, size: 8, color: COLORS[:muted]
      end

      def configure_unicode_font(pdf)
        paths = unicode_font_paths
        pdf.font_families.update(
          UNICODE_FONT_FAMILY => {
            normal: paths[:normal],
            bold: paths[:bold],
            italic: paths[:normal],
            bold_italic: paths[:bold]
          }
        )
        pdf.font(UNICODE_FONT_FAMILY)
      end

      def unicode_font_paths
        override = ENV["WASTAYS_PDF_UNICODE_FONT_PATH"].presence
        candidates = []
        candidates << { normal: override, bold: ENV["WASTAYS_PDF_UNICODE_BOLD_FONT_PATH"].presence || override } if override
        candidates.concat(UNICODE_FONT_CANDIDATES)

        candidates.find { |paths| paths.values.all? { |path| File.file?(path) } } ||
          raise("Unicode PDF font not found. Install fonts-noto-cjk or set WASTAYS_PDF_UNICODE_FONT_PATH.")
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
