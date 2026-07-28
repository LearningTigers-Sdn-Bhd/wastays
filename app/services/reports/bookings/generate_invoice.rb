# frozen_string_literal: true

require "prawn"
require "prawn/table"
require "cgi"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module Bookings
    class GenerateInvoice
      DARK_GREEN = "0a2e29"
      GOLD = "d9c5a0"
      WHITE = "ffffff"
      LIGHT_GRAY = "f9fafb"
      BORDER_GRAY = "e5e7eb"
      TEXT_PRIMARY = "111827"
      TEXT_MUTED = "6b7280"
      SUCCESS = "059669"
      DANGER = "dc2626"
      BOTTOM_MARGIN = 72
      FOOTER_Y = -26

      def initialize(folio:, printed_by: nil, revision_number: nil)
        @records = Reports::Bookings::GenerateFolioRecords.new(
          folio:,
          printed_by:,
          revision_number:
        ).call
      end

      def generate
        pdf = Prawn::Document.new(
          page_size: "A4",
          margin: [ 36, 32, BOTTOM_MARGIN, 32 ],
          info: {
            Title: @records.pdf_title,
            Author: "WAStays",
            Creator: "WAStays",
            CreationDate: Time.current
          }
        )

        render_into(pdf, footer: true)
        pdf.render
      end

      def render_into(pdf, footer: false)
        draw_header(pdf)
        draw_legacy_notice(pdf) if @records.legacy_generated?
        pdf.move_down 14
        draw_hotel_information(pdf)
        pdf.move_down 12
        draw_guest_booking_details(pdf)
        pdf.move_down 18
        draw_transactions(pdf)
        pdf.move_down 16
        draw_summary(pdf)
        pdf.move_down 14
        draw_legend(pdf)
        pdf.move_down 14
        draw_notes(pdf)
        pdf.move_down 18
        draw_signatures(pdf)
        draw_footer(pdf) if footer
        pdf
      end

      private

      def draw_header(pdf)
        logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
        if File.exist?(logo_path)
          pdf.image logo_path, height: 32
        else
          pdf.fill_color DARK_GREEN
          pdf.text "WAStays", size: 22, style: :bold
        end

        pdf.move_up 32
        pdf.fill_color DARK_GREEN
        pdf.text @records.document_title, size: 18, style: :bold, align: :right
        pdf.move_down 12
        pdf.stroke_color DARK_GREEN
        pdf.line_width 0.5
        pdf.stroke_horizontal_rule
        pdf.line_width 1
        pdf.fill_color TEXT_PRIMARY
      end

      def draw_hotel_information(pdf)
        rows = @records.hotel_info_rows
        return if rows.empty?

        section_title(pdf, "HOTEL INFORMATION")
        pdf.table(rows.map { |label, value| [ label_cell(label), value_cell(value) ] }, width: pdf.bounds.width, column_widths: [ 120, pdf.bounds.width - 120 ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 4, 7, 4, 7 ]
          cells.size = 8
          column(0).font_style = :bold
          column(0).text_color = TEXT_MUTED
        end
      end

      def draw_legacy_notice(pdf)
        pdf.move_down 10
        pdf.fill_color "92400e"
        pdf.text "LEGACY-GENERATED RECONSTRUCTION", size: 9, style: :bold, align: :center
        pdf.fill_color TEXT_MUTED
        pdf.text "Reconstructed from currently available records; an original issue-time snapshot was not available.", size: 7.5, align: :center
        pdf.fill_color TEXT_PRIMARY
      end

      def draw_guest_booking_details(pdf)
        left_rows = @records.guest_folio_detail_rows
        right_rows = @records.booking_stay_detail_rows
        row_count = [ left_rows.size, right_rows.size ].max

        rows = [
          [
            { content: "GUEST / FOLIO DETAILS", colspan: 2, font_style: :bold, text_color: TEXT_PRIMARY, background_color: LIGHT_GRAY },
            { content: "BOOKING / STAY DETAILS", colspan: 2, font_style: :bold, text_color: TEXT_PRIMARY, background_color: LIGHT_GRAY }
          ]
        ]

        rows += row_count.times.map do |index|
          left = left_rows[index] || [ "", "" ]
          right = right_rows[index] || [ "", "" ]
          [
            label_cell(left.first),
            value_cell(left.last),
            label_cell(right.first),
            value_cell(right.last)
          ]
        end

        label_width = 82
        value_width = (pdf.bounds.width - (label_width * 2)) / 2.0
        pdf.table(rows, width: pdf.bounds.width, column_widths: [ label_width, value_width, label_width, value_width ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 4, 7, 4, 7 ]
          cells.size = 8
          cells.inline_format = true
          row(0).padding = [ 5, 7, 5, 7 ]
          columns([ 0, 2 ]).font_style = :bold
          columns([ 0, 2 ]).text_color = TEXT_MUTED
        end
      end

      def label_cell(label)
        { content: escape(label.to_s), text_color: TEXT_MUTED, font_style: :bold }
      end

      def value_cell(value)
        { content: escape(value.to_s), text_color: TEXT_PRIMARY }
      end

      def draw_transactions(pdf)
        rows = [
          [
            header_cell("Date"),
            header_cell("Code"),
            header_cell("Description"),
            header_cell("Qty", align: :center),
            header_cell("Net (#{@records.currency})", align: :right),
            header_cell("Charges (#{@records.currency})", align: :right),
            header_cell("Gross (#{@records.currency})", align: :right)
          ]
        ]

        @records.transaction_rows.each do |row|
          rows << [
            body_cell(row.date, color: TEXT_MUTED),
            body_cell(row.code, color: TEXT_MUTED),
            description_cell(row),
            body_cell(row.quantity, align: :center, color: TEXT_MUTED),
            money_cell(row.net),
            money_cell(row.charges),
            money_cell(row.gross, credit: payment_credit?(row))
          ]
        end

        pdf.table(
          rows,
          width: pdf.bounds.width,
          header: true,
          column_widths: transaction_column_widths(pdf)
        ) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 6, 5, 6, 5 ]
          cells.size = 7.5
          row(0).background_color = LIGHT_GRAY
          row(0).font_style = :bold
        end
      end

      def transaction_column_widths(pdf)
        width = pdf.bounds.width
        [
          55,
          86,
          width - 55 - 86 - 28 - 68 - 68 - 72,
          28,
          68,
          68,
          72
        ]
      end

      def header_cell(text, align: :left)
        { content: text, text_color: TEXT_MUTED, align: align }
      end

      def body_cell(text, align: :left, color: TEXT_PRIMARY)
        { content: text.to_s.presence || "-", text_color: color, align: align }
      end

      def description_cell(row)
        content = escape(row.description.to_s)
        content += "\n<font size='6.5'>#{escape(row.secondary_description)}</font>" if row.secondary_description.present?
        { content: content, inline_format: true, text_color: TEXT_PRIMARY }
      end

      def money_cell(amount, credit: false)
        color = credit ? SUCCESS : TEXT_PRIMARY
        { content: money_cell_text(amount, credit: credit), align: :right, text_color: color }
      end

      def payment_credit?(row)
        row.kind == "payment" && row.gross.to_d.positive?
      end

      def money_cell_text(amount, credit:)
        return "-" if amount.blank?
        return @records.credit_amount(amount) if credit

        @records.amount(amount)
      end

      def draw_summary(pdf)
        section_title(pdf, "SUMMARY (#{@records.currency})", width: summary_width(pdf), position: :right)

        rows = @records.summary_rows.map do |row|
          amount = row.credit ? @records.credit_amount(row.amount) : @records.amount(row.amount)
          [
            { content: row.label, font_style: row.emphasis ? :bold : :normal },
            { content: amount, align: :right, font_style: row.emphasis ? :bold : :normal, text_color: row.credit ? SUCCESS : TEXT_PRIMARY }
          ]
        end

        width = summary_width(pdf)
        pdf.table(rows, width: width, position: :right, column_widths: [ width * 0.68, width * 0.32 ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 8, 5, 8 ]
          cells.size = 8
        end
      end

      def draw_legend(pdf)
        legend_rows = @records.legend_rows
        return if legend_rows.empty?

        section_title(pdf, "Transaction Code Legend")

        rows = legend_rows.each_slice(2).map do |pairs|
          pairs.flat_map do |code, label|
            [
              { content: code.to_s, font_style: :bold, text_color: TEXT_PRIMARY },
              { content: label.to_s, text_color: TEXT_MUTED }
            ]
          end.tap do |cells|
            cells << { content: "", borders: [] } while cells.size < 4
          end
        end

        pdf.table(rows, width: pdf.bounds.width, column_widths: [ 60, (pdf.bounds.width - 120) / 2.0, 60, (pdf.bounds.width - 120) / 2.0 ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 4, 6, 4, 6 ]
          cells.size = 7.5
        end
      end

      def draw_notes(pdf)
        notes = @records.notes
        return if notes.empty?

        section_title(pdf, "Notes")
        pdf.table(notes.map { |note| [ { content: note, text_color: TEXT_MUTED } ] }, width: pdf.bounds.width) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 8, 5, 8 ]
          cells.size = 8
        end
      end

      def draw_signatures(pdf)
        row = [
          { content: "Guest Signature\n\n\n", font_style: :bold, text_color: TEXT_PRIMARY },
          { content: "Authorised Signature\n\n\n", font_style: :bold, text_color: TEXT_PRIMARY }
        ]

        pdf.table([ row ], width: pdf.bounds.width, column_widths: [ pdf.bounds.width / 2.0, pdf.bounds.width / 2.0 ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 8, 8, 8, 8 ]
          cells.size = 8
        end
      end

      def draw_footer(pdf)
        pdf.repeat(:all) do
          pdf.stroke_color BORDER_GRAY
          pdf.line_width 0.5
          pdf.stroke_horizontal_line(pdf.bounds.left, pdf.bounds.right, at: FOOTER_Y + 14)

          pdf.bounding_box([ pdf.bounds.left, FOOTER_Y ], width: pdf.bounds.width - 88, height: 12) do
            pdf.fill_color TEXT_MUTED
            pdf.text printed_at_text, size: 7, align: :left
          end
        end

        pdf.number_pages "Page <page> of <total>",
          at: [ pdf.bounds.right - 75, FOOTER_Y ],
          size: 7,
          color: TEXT_MUTED
      end

      def printed_at_text
        "Printed at #{Time.current.strftime('%d %b %Y %H:%M')} by #{@records.printed_by}"
      end

      def summary_width(pdf)
        pdf.bounds.width * 0.48
      end

      def section_title(pdf, title, width: pdf.bounds.width, position: nil)
        pdf.table(
          [ [ { content: title, font_style: :bold, text_color: TEXT_PRIMARY } ] ],
          width: width,
          position: position
        ) do
          cells.background_color = LIGHT_GRAY
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 8, 5, 8 ]
          cells.size = 8
        end
      end

      def escape(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
