# frozen_string_literal: true

require "prawn"
require "prawn/table"

module Reports
  module Bookings
    class GenerateInvoicePackage
      InvalidPackageError = Class.new(StandardError)

      DARK_GREEN = GenerateInvoice::DARK_GREEN
      LIGHT_GRAY = GenerateInvoice::LIGHT_GRAY
      BORDER_GRAY = GenerateInvoice::BORDER_GRAY
      TEXT_PRIMARY = GenerateInvoice::TEXT_PRIMARY
      TEXT_MUTED = GenerateInvoice::TEXT_MUTED
      BOTTOM_MARGIN = GenerateInvoice::BOTTOM_MARGIN
      FOOTER_Y = GenerateInvoice::FOOTER_Y

      def initialize(hotel:, folio_invoice_ids:, printed_by: nil)
        @hotel = hotel
        @invoice_ids = Array(folio_invoice_ids).map(&:to_i)
        @printed_by = printed_by.presence || "-"
      end

      def generate
        load_invoices
        validate!
        pdf = Prawn::Document.new(
          page_size: "A4",
          margin: [ 36, 32, BOTTOM_MARGIN, 32 ],
          info: {
            Title: "Invoice package - #{recipient.name}",
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

      def load_invoices
        raise InvalidPackageError, "Duplicate invoices are not allowed." if @invoice_ids.uniq.size != @invoice_ids.size

        records = @hotel.folio_invoices
          .where(id: @invoice_ids)
          .includes(
            :revisions,
            booking_folio: [
              :ar_invoice,
              :booking_room,
              { booking: [ :booking_rooms, { booking_guests: :guest } ] },
              { booking_billing_party: [ { booking_guest: :guest }, { hotel_corporate_account: { corporate_account: :users } } ] },
              { hotel_corporate_account: { corporate_account: :users } }
            ]
          )
          .index_by(&:id)
        @invoices = @invoice_ids.filter_map { |id| records[id] }
        raise InvalidPackageError, "One or more invoices do not belong to this hotel." unless @invoices.size == @invoice_ids.size

        @invoices.sort_by! { |invoice| [ invoice.booking.id, invoice.booking_folio.folio_sequence.to_i, invoice.id ] }
      end

      def validate!
        raise InvalidPackageError, "Select at least one finalized invoice." if @invoices.empty?

        hotel_ids = @invoices.map(&:hotel_id).uniq
        raise InvalidPackageError, "All invoices must belong to the same hotel." unless hotel_ids.one?

        keys = @invoices.map { |invoice| FolioInvoicePackages::RecipientResolver.call(invoice).key }.uniq
        raise InvalidPackageError, "All invoices in a package must belong to the same payer." unless keys.one?

        @invoices.each do |invoice|
          folio = invoice.booking_folio
          valid = invoice.finalized? && folio.closed? && folio.ar_invoice.blank? && invoice.current_revision.present?
          raise InvalidPackageError, "Invoice #{invoice.invoice_reference} is no longer available to send." unless valid
        end
      end

      def recipient
        @recipient ||= FolioInvoicePackages::RecipientResolver.call(@invoices.first)
      end

      def draw_summary(pdf)
        pdf.fill_color DARK_GREEN
        pdf.text "INVOICE PACKAGE", size: 18, style: :bold
        pdf.move_down 5
        pdf.fill_color TEXT_MUTED
        pdf.text "Prepared for #{recipient.name}", size: 10
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
        snapshot = invoice.current_revision.snapshot.to_h.deep_stringify_keys
        folio = invoice.booking_folio
        booking = folio.booking
        rooms = Array(snapshot["rooms"]).filter_map do |room|
          values = room.to_h.stringify_keys
          [ values["room_number"], values["room_type"] ].compact_blank.join(" / ").presence
        end
        amount = snapshot.dig("totals", "charges").to_d + snapshot.dig("totals", "adjustments").to_d

        [
          invoice.current_document_reference,
          [ booking.formatted_reservation_number.presence || booking.confirmation_token, rooms.to_sentence.presence || "Unassigned" ].join(" · "),
          recipient.name,
          snapshot.dig("totals", "currency").presence || folio.currency,
          format("%.2f", amount)
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
        invoice.current_revision.snapshot.to_h.dig("totals", "currency").presence || invoice.booking_folio.currency
      end

      def invoice_amount(invoice)
        totals = invoice.current_revision.snapshot.to_h.fetch("totals", {})
        totals["charges"].to_d + totals["adjustments"].to_d
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
