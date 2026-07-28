# frozen_string_literal: true

require "cgi"
require "prawn"
require "prawn/table"

module Reports
  module AccountsReceivable
    class GenerateInvoice
      DARK_GREEN = "0a2e29"
      LIGHT_GRAY = "f9fafb"
      BORDER_GRAY = "e5e7eb"
      TEXT_PRIMARY = "111827"
      TEXT_MUTED = "6b7280"
      BOTTOM_MARGIN = 60

      def initialize(invoice:, printed_by: nil)
        @records = GenerateInvoiceRecords.new(invoice:, printed_by:)
      end

      def generate
        pdf = Prawn::Document.new(
          page_size: "A4",
          margin: [ 36, 32, BOTTOM_MARGIN, 32 ],
          info: {
            Title: "AR Invoice - #{@records.invoice_reference}",
            Author: "WAStays",
            Creator: "WAStays",
            CreationDate: Time.current
          }
        )

        draw_header(pdf)
        draw_legacy_notice(pdf) if @records.legacy_generated?
        pdf.move_down 16
        draw_parties(pdf)
        pdf.move_down 14
        draw_references(pdf)
        pdf.move_down 16
        draw_lines(pdf)
        pdf.move_down 16
        draw_totals(pdf)
        draw_footer(pdf)
        pdf.render
      end

      private

      def draw_legacy_notice(pdf)
        pdf.move_down 10
        pdf.fill_color "92400e"
        pdf.text "LEGACY-GENERATED RECONSTRUCTION", size: 9, style: :bold, align: :center
        pdf.fill_color TEXT_MUTED
        pdf.text "Reconstructed from currently available records; an original issue-time snapshot was not available.", size: 7.5, align: :center
        pdf.fill_color TEXT_PRIMARY
      end

      def draw_header(pdf)
        pdf.fill_color DARK_GREEN
        pdf.text "ACCOUNTS RECEIVABLE INVOICE", size: 17, style: :bold
        pdf.move_down 5
        pdf.text @records.invoice_reference, size: 11, style: :bold
        pdf.fill_color TEXT_MUTED
        pdf.text "Status: #{@records.status}", size: 9
        pdf.move_down 10
        pdf.stroke_color DARK_GREEN
        pdf.stroke_horizontal_rule
        pdf.fill_color TEXT_PRIMARY
      end

      def draw_parties(pdf)
        rows = [
          [ label("Corporate Payer"), value(@records.company_name), label("Account Type"), value(@records.account_type) ],
          [ label("Issue Date"), value(@records.issued_on), label("Due Date"), value(@records.due_on) ],
          [ label("Payment Terms"), value(@records.payment_terms), label("Currency"), value(@records.currency) ]
        ]
        details_table(pdf, rows)
      end

      def draw_references(pdf)
        section_title(pdf, "SOURCE REFERENCES")
        rows = [
          [ label("Booking"), value(@records.booking_reference), label("Folio"), value(@records.folio_reference) ],
          [ label("Room"), value(@records.room_reference), label("Purchase Order"), value(@records.purchase_order_reference) ],
          [ label("Authorization"), value(@records.authorization_reference), label(""), value("") ]
        ]
        details_table(pdf, rows)
      end

      def draw_lines(pdf)
        section_title(pdf, "FOLIO CHARGES AND CREDITS")
        rows = [ [ header("Date"), header("Code"), header("Description"), header("Amount (#{@records.currency})", align: :right) ] ]
        rows += @records.lines.map do |line|
          [ body(line.date), body(line.code), body(line.description), body(money(line.amount), align: :right) ]
        end
        rows << [ { content: "No folio transaction lines recorded.", colspan: 4, text_color: TEXT_MUTED } ] if @records.lines.empty?
        rows << [
          { content: "BALANCE TRANSFERRED TO AR", colspan: 3, font_style: :bold, background_color: LIGHT_GRAY },
          body(money(@records.line_total), align: :right).merge(font_style: :bold, background_color: LIGHT_GRAY)
        ]

        pdf.table(rows, width: pdf.bounds.width, header: true, column_widths: [ 75, 75, pdf.bounds.width - 245, 95 ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 6, 7 ]
          cells.size = 8
          row(0).background_color = LIGHT_GRAY
          row(0).font_style = :bold
        end
      end

      def draw_totals(pdf)
        width = pdf.bounds.width * 0.46
        rows = [
          [ "Original Amount", money(@records.original_amount) ],
          [ "Paid Amount", money(@records.paid_amount) ],
          [ "Outstanding Amount", money(@records.outstanding_amount) ]
        ]
        pdf.table(rows, width:, position: :right, column_widths: [ width * 0.62, width * 0.38 ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 6, 8 ]
          cells.size = 8
          column(1).align = :right
          row(2).font_style = :bold
          row(2).background_color = LIGHT_GRAY
        end
      end

      def draw_footer(pdf)
        pdf.repeat(:all) do
          pdf.bounding_box([ pdf.bounds.left, -28 ], width: pdf.bounds.width, height: 14) do
            pdf.fill_color TEXT_MUTED
            pdf.text "Printed at #{Time.current.strftime('%d %b %Y %H:%M')} by #{@records.printed_by}", size: 7
          end
        end
        pdf.number_pages "Page <page> of <total>", at: [ pdf.bounds.right - 75, -28 ], size: 7, color: TEXT_MUTED
      end

      def details_table(pdf, rows)
        label_width = 88
        value_width = (pdf.bounds.width - (label_width * 2)) / 2.0
        pdf.table(rows, width: pdf.bounds.width, column_widths: [ label_width, value_width, label_width, value_width ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 7 ]
          cells.size = 8
        end
      end

      def section_title(pdf, text)
        pdf.fill_color DARK_GREEN
        pdf.text text, size: 9, style: :bold
        pdf.fill_color TEXT_PRIMARY
        pdf.move_down 5
      end

      def label(text)
        { content: escape(text), font_style: :bold, text_color: TEXT_MUTED }
      end

      def value(text)
        { content: escape(text.to_s.presence || "-") }
      end

      def header(text, align: :left)
        { content: escape(text), text_color: TEXT_MUTED, align: }
      end

      def body(text, align: :left)
        { content: escape(text.to_s.presence || "-"), align: }
      end

      def money(amount)
        format("%.2f", amount.to_d)
      end

      def escape(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
