# frozen_string_literal: true

require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

# Wears the shared print design system (DESIGN.md §12). The voucher draws its own body
# rather than going through PdfReportBuilder: the parties it names do not fit a metadata
# strip, and its charge is a single line rather than the tabular period report the builder
# owns.
#
# It prints twice. The guest keeps one copy and the hotel files the other, so both carry a
# full masthead and are labelled for whom they are.
module Reports
  module Bookings
    class GenerateTourismTaxVoucher
      THEME = HotelPortal::Reports::Exports::PdfTheme

      COPIES = [ "Guest copy", "Hotel copy" ].freeze
      QUANTITY_WIDTH = 56
      RATE_WIDTH = 86
      AMOUNT_WIDTH = 86

      def initialize(booking:, printed_by: nil)
        @records = Reports::Bookings::GenerateTourismTaxVoucherRecords.new(
          booking: booking,
          printed_by: printed_by
        ).call
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: THEME::PAGE_MARGIN, info: document_info)
        THEME.configure_font(pdf)

        frame = nil
        COPIES.each_with_index do |copy, index|
          pdf.start_new_page unless index.zero?
          frame = draw_copy(pdf, copy)
        end
        # Every page opens a copy of its own, so none of them is a continuation needing a
        # running head to say what it belongs to.
        frame.stamp_page_furniture(masthead_pages: (1..pdf.page_count).to_a)
        pdf.render
      end

      private

      def document_info
        {
          Title: @records.pdf_title,
          Author: "WAStays",
          Creator: "WAStays",
          CreationDate: Time.current
        }
      end

      def draw_copy(pdf, copy)
        frame = build_frame(pdf, copy)
        frame.draw_header
        HotelPortal::Reports::Exports::PdfPartyBlocks.new(pdf: pdf).draw(@records.party_blocks)
        draw_charges(pdf)
        draw_signatures(pdf)
        draw_closing_note(pdf)
        frame
      end

      # The voucher number is the title; the eyebrow says what the number belongs to, and the
      # status badge sits against it. Which copy this sheet is goes higher still, opposite the
      # hotel identity: it is a fact about the paper rather than about the document, and
      # whoever is filing it should not have to read as far as the title to sort it. The
      # parties go in blocks of their own, so the frame draws no metadata strip above them.
      def build_frame(pdf, copy)
        HotelPortal::Reports::Exports::PdfReportFrame.new(
          pdf: pdf,
          hotel: @records.hotel,
          hotel_identifiers: @records.hotel_identifier_line,
          eyebrow: "Tourism tax voucher",
          report_name: @records.voucher_number,
          masthead_badge: { label: copy, variant: :outline },
          badge: @records.status_badge,
          metadata: [],
          # Goes home with the guest, not into the hotel's filing cabinet.
          confidential: false
        )
      end

      def draw_charges(pdf)
        currency = @records.currency
        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Tourism tax",
          headers: [ "Particulars", "Room nights", "Rate (#{currency})", "Amount (#{currency})" ],
          rows: @records.charge_rows.map { |row| charge_row(row) },
          numeric_columns: [ 1, 2, 3 ],
          total_row: @records.total_row,
          empty_message: "No tourism tax has been posted for this stay.",
          column_widths: column_widths(pdf),
          density: :dense
        )
      end

      # A quantity or rate the snapshot cannot supply prints as a dash rather than as a number
      # worked back from the total.
      def charge_row(row)
        [ row.description, row.quantity || "-", row.rate || "-", row.amount ]
      end

      def column_widths(pdf)
        described = pdf.bounds.width - QUANTITY_WIDTH - RATE_WIDTH - AMOUNT_WIDTH
        [ described, QUANTITY_WIDTH, RATE_WIDTH, AMOUNT_WIDTH ]
      end

      def draw_signatures(pdf)
        HotelPortal::Reports::Exports::PdfSignatureBlock.new(pdf: pdf).draw(
          fields: [ { label: "Guest signature" }, { label: "Authorised signature" } ]
        )
      end

      def draw_closing_note(pdf)
        pdf.fill_color THEME::COLORS[:muted]
        pdf.text @records.closing_note, size: THEME::TYPE[:micro]
        pdf.fill_color THEME::COLORS[:ink]
      end
    end
  end
end
