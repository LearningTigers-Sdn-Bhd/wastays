# frozen_string_literal: true

require "prawn"
require "prawn/table"

module Reports
  module Bookings
    class GenerateCombinedInvoices
      InvalidCombinedInvoicesError = Class.new(StandardError)

      DARK_GREEN = GenerateInvoice::DARK_GREEN
      LIGHT_GRAY = GenerateInvoice::LIGHT_GRAY
      BORDER_GRAY = GenerateInvoice::BORDER_GRAY
      TEXT_PRIMARY = GenerateInvoice::TEXT_PRIMARY
      TEXT_MUTED = GenerateInvoice::TEXT_MUTED
      BOTTOM_MARGIN = GenerateInvoice::BOTTOM_MARGIN
      FOOTER_Y = GenerateInvoice::FOOTER_Y

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
          margin: [ 36, 32, BOTTOM_MARGIN, 32 ],
          info: {
            Title: "Combined invoices - #{@recipient.name}",
            Author: "WAStays",
            Creator: "WAStays",
            CreationDate: Time.current
          }
        )

        draw_summary(pdf)
        @invoices.each do |invoice|
          pdf.start_new_page
          GenerateInvoice.new(folio: invoice.booking_folio, printed_by: @printed_by).render_into(pdf)
        end
        draw_footer(pdf)
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

      def draw_summary(pdf)
        pdf.fill_color DARK_GREEN
        pdf.text "COMBINED INVOICES", size: 18, style: :bold
        pdf.move_down 5
        pdf.fill_color TEXT_MUTED
        pdf.text "Prepared for #{@recipient.name}", size: 10
        pdf.move_down 12
        pdf.stroke_color DARK_GREEN
        pdf.stroke_horizontal_rule
        pdf.fill_color TEXT_PRIMARY
        pdf.move_down 18

        rows = [
          [ "Invoice", "Booking / room", "Payer", "Currency", "Amount" ].map { |label| header_cell(label) }
        ]
        rows.concat(@invoices.map { |invoice| summary_row(invoice) })

        pdf.table(rows, width: pdf.bounds.width, header: true, column_widths: summary_widths(pdf)) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 6, 6 ]
          cells.size = 7.5
          row(0).background_color = LIGHT_GRAY
          row(0).font_style = :bold
          column(4).align = :right
        end

        pdf.move_down 16
        draw_currency_totals(pdf)
        pdf.move_down 12
        pdf.fill_color TEXT_MUTED
        pdf.text "Each invoice that follows keeps its own official invoice number.", size: 8
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
          format("%.2f", records.total_due)
        ]
      end

      def draw_currency_totals(pdf)
        totals = @invoices.group_by { |invoice| invoice_currency(invoice) }.transform_values do |invoices|
          invoices.sum { |invoice| invoice_amount(invoice) }
        end
        width = pdf.bounds.width * 0.45
        rows = totals.sort.map do |currency, amount|
          [ { content: "Total (#{currency})", font_style: :bold }, { content: format("%.2f", amount), align: :right, font_style: :bold } ]
        end
        pdf.table(rows, width:, position: :right, column_widths: [ width * 0.62, width * 0.38 ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 6, 8 ]
          cells.size = 8
        end
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

      def header_cell(value)
        { content: value, text_color: TEXT_MUTED }
      end

      def draw_footer(pdf)
        pdf.repeat(:all) do
          pdf.stroke_color BORDER_GRAY
          pdf.line_width 0.5
          pdf.stroke_horizontal_line(pdf.bounds.left, pdf.bounds.right, at: FOOTER_Y + 14)
          pdf.bounding_box([ pdf.bounds.left, FOOTER_Y ], width: pdf.bounds.width - 88, height: 12) do
            pdf.fill_color TEXT_MUTED
            pdf.text "Prepared at #{Time.current.strftime('%d %b %Y %H:%M')} by #{@printed_by}", size: 7
          end
        end
        pdf.number_pages "Page <page> of <total>", at: [ pdf.bounds.right - 75, FOOTER_Y ], size: 7, color: TEXT_MUTED
      end
    end
  end
end
