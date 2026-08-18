# frozen_string_literal: true

require "prawn"
require "prawn/table"
require "cgi"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module Bookings
    # Wears the shared print design system (DESIGN.md §12). It draws its own body rather
    # than going through PdfReportBuilder: the parties it bills do not fit a metadata
    # strip, and it ends on two blocks set against the right margin rather than on a
    # full-measure table.
    #
    # Four documents share this body — the folio invoice, the AR invoice, the guest's own
    # copy, and the combined pack — so #render_into draws into a document it does not own.
    class GenerateInvoice
      THEME = HotelPortal::Reports::Exports::PdfTheme

      # Seven columns in portrait, so the table takes the dense step of the scale. Date is
      # sized to a four-figure year and code to a composite like RM-ACC_SVC-CHG; every point
      # neither needs goes to the description, which is the column that actually wraps.
      FIXED_COLUMN_WIDTHS = { date: 64, code: 76, quantity: 28, money: 66, gross: 70 }.freeze
      SUMMARY_WIDTH_FRACTION = 0.48
      SUMMARY_LABEL_FRACTION = 0.62
      STATUS_WIDTH_FRACTION = 0.54
      SIGNATURE_SPACE = THEME::SPACE[:xl] * 2

      LEGACY_LABEL = "RECONSTRUCTED FROM RECORDS"
      LEGACY_NOTE = "Rebuilt from currently available records; an original issue-time snapshot was not available."
      STATUS_NOTE = "This dated status is not part of the immutable issued invoice body."

      def initialize(folio: nil, invoice: nil, receivable: nil, printed_by: nil, revision_number: nil)
        @records = Reports::Bookings::GenerateFolioRecords.new(
          folio:,
          invoice:,
          receivable:,
          printed_by:,
          revision_number:
        ).call
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: THEME::PAGE_MARGIN, info: document_info)
        THEME.configure_font(pdf)
        render_into(pdf, footer: true)
        pdf.render
      end

      # The combined pack stamps page furniture once for the whole document, so it asks for
      # the body alone.
      def render_into(pdf, footer: false)
        frame = build_frame(pdf)
        frame.draw_header
        draw_legacy_notice(pdf) if @records.legacy_generated?
        HotelPortal::Reports::Exports::PdfPartyBlocks.new(pdf: pdf).draw(@records.party_blocks)
        draw_transactions(pdf)
        draw_summary(pdf)
        draw_current_payment_status(pdf) if @records.direct_bill?
        draw_notes(pdf)
        draw_printed_at(pdf)
        draw_signatures(pdf)
        frame.stamp_page_furniture if footer
        pdf
      end

      private

      def document_info
        { Title: @records.pdf_title, Author: "WAStays", Creator: "WAStays", CreationDate: Time.current }
      end

      # The invoice number is the title; the eyebrow says what kind of invoice it is. The
      # parties go in blocks of their own, so the frame draws no metadata strip above them.
      def build_frame(pdf)
        HotelPortal::Reports::Exports::PdfReportFrame.new(
          pdf: pdf,
          hotel: @records.pdf_hotel,
          hotel_contact: @records.hotel_contact_line,
          eyebrow: @records.document_kind,
          report_name: @records.invoice_number,
          metadata: [],
          # Goes to the guest or the corporate payer, not into the hotel's filing cabinet.
          confidential: false
        )
      end

      def draw_legacy_notice(pdf)
        HotelPortal::Reports::Exports::PdfNoticeBand.new(pdf: pdf)
          .draw(label: LEGACY_LABEL, note: LEGACY_NOTE, variant: :warning)
      end

      def draw_transactions(pdf)
        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Transactions",
          headers: [
            "Date", "Code", "Description", "Qty",
            "Net (#{@records.currency})", "Charges (#{@records.currency})", "Gross (#{@records.currency})"
          ],
          rows: @records.transaction_rows.map { |row| transaction_row(row) },
          numeric_columns: [ 3, 4, 5, 6 ],
          total_row: nil,
          empty_message: "No transactions were posted to this folio.",
          column_widths: transaction_column_widths(pdf),
          density: :dense
        )
      end

      def transaction_row(row)
        [
          row.date,
          row.code.to_s.presence || "-",
          description_cell(row),
          row.quantity.to_s.presence || "-",
          money_text(row.net),
          money_text(row.charges),
          money_text(row.gross, credit: payment_credit?(row))
        ]
      end

      # The only cell carrying more than one value: what the charge covers sits under the
      # charge itself, a step down the scale, rather than taking a column of its own.
      def description_cell(row)
        content = escape(row.description.to_s)
        if row.secondary_description.present?
          content += "\n<font size='#{THEME::TYPE[:micro]}'>#{escape(row.secondary_description)}</font>"
        end
        { content: content, inline_format: true }
      end

      def transaction_column_widths(pdf)
        fixed = FIXED_COLUMN_WIDTHS
        described = pdf.bounds.width - fixed[:date] - fixed[:code] - fixed[:quantity] -
                    (fixed[:money] * 2) - fixed[:gross]
        [ fixed[:date], fixed[:code], described, fixed[:quantity], fixed[:money], fixed[:money], fixed[:gross] ]
      end

      def payment_credit?(row) = row.kind == "payment" && row.gross.to_d.positive?

      # Credits are marked by parentheses alone. The theme has no positive colour on
      # purpose, and a bracketed amount already says which way the money went.
      def money_text(amount, credit: false)
        return "-" if amount.blank?

        credit ? @records.credit_amount(amount) : @records.amount(amount)
      end

      def draw_summary(pdf)
        rows = @records.summary_rows
        width = pdf.bounds.width * SUMMARY_WIDTH_FRACTION
        label_width = (width * SUMMARY_LABEL_FRACTION).floor

        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Summary (#{@records.currency})",
          headers: [ "", "" ],
          rows: rows.map { |row| [ row.label, summary_amount(row) ] },
          numeric_columns: [ 1 ],
          total_row: nil,
          empty_message: "No amounts to summarise.",
          column_widths: [ label_width, width - label_width ],
          # Total Due and Balance are what the reader is looking for; the lines above are
          # how they were reached.
          row_variants: rows.each_with_index.to_h { |row, index| [ index, row.emphasis ? :subtotal : nil ] }.compact,
          position: :right,
          show_header: false
        )
      end

      def summary_amount(row)
        row.credit ? @records.credit_amount(row.amount) : @records.amount(row.amount)
      end

      def draw_current_payment_status(pdf)
        rows = @records.current_payment_status_rows
        return if rows.empty?

        width = pdf.bounds.width * STATUS_WIDTH_FRACTION
        label_width = (width * SUMMARY_LABEL_FRACTION).floor

        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Current payment status",
          headers: [ "", "" ],
          rows: rows,
          numeric_columns: [ 1 ],
          total_row: nil,
          empty_message: "",
          column_widths: [ label_width, width - label_width ],
          row_variants: { 3 => :subtotal },
          position: :right,
          show_header: false
        )
        draw_muted_line(pdf, STATUS_NOTE)
        pdf.move_down THEME::SPACE[:lg]
      end

      # Prose, not data: a border around a sentence is chrome for nothing.
      def draw_notes(pdf)
        notes = @records.notes
        return if notes.empty?

        notes.each { |note| draw_muted_line(pdf, note) }
        pdf.move_down THEME::SPACE[:lg]
      end

      # The issue date is a fact about the invoice and sits with the invoice details; this
      # is a fact about the sheet of paper, so it sits at the foot on its own.
      def draw_printed_at(pdf)
        draw_muted_line(pdf, "Printed #{@records.printed_at}")
        pdf.move_down THEME::SPACE[:lg]
      end

      def draw_muted_line(pdf, text)
        pdf.fill_color THEME::COLORS[:muted]
        pdf.text text, size: THEME::TYPE[:micro]
        pdf.fill_color THEME::COLORS[:ink]
      end

      # A rule to sign above, with its label beneath — the bordered box this used to draw
      # read as another data table.
      def draw_signatures(pdf)
        pdf.start_new_page if pdf.cursor < SIGNATURE_SPACE + THEME::SPACE[:xl]
        pdf.move_down SIGNATURE_SPACE

        column_width = (pdf.bounds.width - THEME::SPACE[:xl]) / 2.0
        top = pdf.cursor
        pdf.stroke_color THEME::COLORS[:border]
        pdf.line_width THEME::RULE_WIDTH
        [ [ 0, "Guest signature" ], [ column_width + THEME::SPACE[:xl], "Authorised signature" ] ].each do |left, label|
          pdf.stroke_horizontal_line left, left + column_width, at: top
          pdf.fill_color THEME::COLORS[:muted]
          pdf.text_box label.upcase, at: [ left, top - THEME::SPACE[:xs] ], width: column_width,
            height: THEME::TYPE[:micro] + THEME::SPACE[:xs],
            size: THEME::TYPE[:micro], style: :bold, character_spacing: THEME::LABEL_TRACKING
        end
        pdf.move_cursor_to top - THEME::SPACE[:lg]
        pdf.fill_color THEME::COLORS[:ink]
      end

      def escape(value) = CGI.escapeHTML(value.to_s)
    end
  end
end
