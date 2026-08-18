# frozen_string_literal: true

require "prawn"
require "prawn/table"

module Reports
  module Bookings
    class GenerateCombinedInvoices
      InvalidCombinedInvoicesError = Class.new(StandardError)

      THEME = HotelPortal::Reports::Exports::PdfTheme

      TOTALS_WIDTH_FRACTION = 0.45
      TOTALS_LABEL_FRACTION = 0.62
      CLOSING_NOTE = "Each invoice that follows keeps its own official invoice number."

      def initialize(hotel:, invoices:, recipient:, printed_by: nil)
        @hotel = hotel
        @invoices = Array(invoices)
        @recipient = recipient
        @printed_by = printed_by.presence || "-"
      end

      def generate
        validate!
        @invoices.sort_by! { |invoice| [ invoice.booking.id, invoice.booking_folio.folio_sequence.to_i, invoice.id ] }
        pdf = Prawn::Document.new(
          page_size: "A4",
          margin: THEME::PAGE_MARGIN,
          info: {
            Title: "Combined invoices - #{@recipient.name}",
            Author: "WAStays",
            Creator: "WAStays",
            CreationDate: Time.current
          }
        )
        THEME.configure_font(pdf)

        frame = cover_frame(pdf)
        frame.draw_header
        draw_summary(pdf)
        @invoices.each do |invoice|
          pdf.start_new_page
          GenerateInvoice.new(folio: invoice.booking_folio, printed_by: @printed_by).render_into(pdf)
        end
        # Stamped once for the whole pack: each invoice draws its body but leaves the page
        # furniture alone, or every page would carry as many footers as there are invoices.
        frame.stamp_page_furniture
        pdf.render
      end

      private

      def validate!
        raise InvalidCombinedInvoicesError, "Select at least one finalized invoice." if @invoices.empty?
        raise InvalidCombinedInvoicesError, "Recipient is required." if @recipient.blank?

        hotel_ids = @invoices.map(&:hotel_id).uniq
        raise InvalidCombinedInvoicesError, "All invoices must belong to this hotel." unless hotel_ids == [ @hotel.id ]
        raise InvalidCombinedInvoicesError, "Duplicate invoices are not allowed." unless @invoices.map(&:id).uniq.size == @invoices.size

        @invoices.each do |invoice|
          folio = invoice.booking_folio
          valid = invoice.kind_settled? && invoice.finalized? && folio.closed? && invoice.current_revision.present?
          raise InvalidCombinedInvoicesError, "Invoice #{invoice.invoice_reference} is no longer available to send." unless valid
        end
      end

      # The cover names the recipient and what the pack is; the invoices that follow each
      # draw their own masthead for the hotel that issued them.
      def cover_frame(pdf)
        HotelPortal::Reports::Exports::PdfReportFrame.new(
          pdf: pdf,
          hotel: @hotel,
          eyebrow: "Combined invoices",
          report_name: @recipient.name,
          metadata: [
            [ "Invoices", @invoices.size.to_s ],
            [ "Prepared by", @printed_by ],
            [ "Prepared", THEME.format_time(Time.current, @hotel.hotel_time_zone) ]
          ],
          confidential: false
        )
      end

      def draw_summary(pdf)
        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Invoices in this pack",
          headers: [ "Invoice", "Booking / room", "Payer", "Currency", "Amount" ],
          rows: @invoices.map { |invoice| summary_row(invoice) },
          numeric_columns: [ 4 ],
          total_row: nil,
          empty_message: "No invoices in this pack.",
          column_widths: summary_widths(pdf),
          density: :dense
        )

        draw_currency_totals(pdf)
        pdf.fill_color THEME::COLORS[:muted]
        pdf.text CLOSING_NOTE, size: THEME::TYPE[:micro]
        pdf.fill_color THEME::COLORS[:ink]
      end

      def summary_row(invoice)
        folio = invoice.booking_folio
        booking = folio.booking
        records = invoice_records(invoice)
        snapshot = invoice.current_revision.snapshot.to_h.deep_stringify_keys
        rooms = Array(snapshot["rooms"]).filter_map do |room|
          values = room.to_h.stringify_keys
          [ values["room_number"], values["room_type"] ].compact_blank.join(" / ").presence
        end
        rooms = booking.booking_rooms.map do |room|
          [ room.room_number, room.room_type_snapshot.to_h.with_indifferent_access[:name] || room.room_type&.name ].compact_blank.join(" / ").presence
        end.compact if rooms.empty?

        [
          invoice.current_document_reference,
          [ booking.formatted_reservation_number.presence || booking.confirmation_token, rooms.to_sentence.presence || "Room unavailable" ].join(" · "),
          @recipient.name,
          records.currency,
          THEME.money(records.total_due)
        ]
      end

      def draw_currency_totals(pdf)
        totals = @invoices.group_by { |invoice| invoice_currency(invoice) }.transform_values do |invoices|
          invoices.sum { |invoice| invoice_amount(invoice) }
        end
        return if totals.empty?

        width = pdf.bounds.width * TOTALS_WIDTH_FRACTION
        label_width = (width * TOTALS_LABEL_FRACTION).floor
        rows = totals.sort.map { |currency, amount| [ "Total (#{currency})", THEME.money(amount) ] }

        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: nil,
          headers: [ "", "" ],
          rows: rows,
          numeric_columns: [ 1 ],
          total_row: nil,
          empty_message: "",
          column_widths: [ label_width, width - label_width ],
          row_variants: rows.each_index.to_h { |index| [ index, :subtotal ] },
          position: :right,
          show_header: false
        )
      end

      def invoice_currency(invoice)
        invoice_records(invoice).currency
      end

      def invoice_amount(invoice)
        invoice_records(invoice).total_due
      end

      def invoice_records(invoice)
        @invoice_records ||= {}
        @invoice_records[invoice.id] ||= GenerateFolioRecords.new(folio: invoice.booking_folio, printed_by: @printed_by).call
      end

      def summary_widths(pdf)
        width = pdf.bounds.width
        [ 100, width - 100 - 100 - 62 - 72, 100, 62, 72 ]
      end
    end
  end
end
