# frozen_string_literal: true

require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module AccountsReceivable
    class GenerateGroupStatement
      ValidationError = Class.new(StandardError)

      def initialize(hotel:, group_booking:, ar_invoice_ids:, printed_by: nil)
        @hotel = hotel
        @group_booking = group_booking
        @raw_ids = Array(ar_invoice_ids).map(&:to_s)
        @printed_by = printed_by
      end

      def generate
        validate_and_load!
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 36, 32, 52, 32 ])
        draw_header(pdf)
        draw_invoices(pdf)
        draw_footer(pdf)
        pdf.render
      end

      private

      def validate_and_load!
        raise ValidationError, "Select at least one AR invoice." if @raw_ids.empty?
        raise ValidationError, "Duplicate AR invoices are not allowed." if @raw_ids.uniq.size != @raw_ids.size

        @invoices = ArInvoice
          .includes(:hotel, { hotel_corporate_account: :corporate_account }, booking_folio: :booking)
          .where(id: @raw_ids)
          .order(:issued_on, :id)
          .to_a
        raise ValidationError, "One or more selected AR invoices no longer exist." unless @invoices.size == @raw_ids.size
        raise ValidationError, "Selected AR invoices must belong to this hotel." unless @invoices.all? { |invoice| invoice.hotel_id == @hotel.id }
        raise ValidationError, "Voided AR invoices cannot be included." if @invoices.any?(&:void?)
        raise ValidationError, "Selected AR invoices must belong to this booking group." unless @invoices.all? { |invoice| invoice.booking.group_booking_id == @group_booking.id }
        raise ValidationError, "Selected AR invoices must use one corporate account." unless @invoices.map(&:hotel_corporate_account_id).uniq.one?
        raise ValidationError, "Selected AR invoices must use one currency." unless @invoices.map(&:currency).uniq.one?

        @account = @invoices.first.corporate_account
        @currency = @invoices.first.currency
      end

      def draw_header(pdf)
        pdf.fill_color "0a2e29"
        pdf.text "GROUP ACCOUNTS RECEIVABLE STATEMENT", size: 17, style: :bold
        pdf.move_down 5
        pdf.text @group_booking.formatted_reservation_number.to_s, size: 11, style: :bold
        pdf.fill_color "111827"
        pdf.move_down 16
        pdf.table(
          [
            [ "Corporate account", @account.name.to_s, "Currency", @currency ],
            [ "Generated", I18n.l(Date.current, format: :long), "Invoices", @invoices.size.to_s ]
          ],
          width: pdf.bounds.width,
          cell_style: { size: 9, padding: [ 5, 6 ], border_color: "e5e7eb" },
          column_widths: [ 100, 186, 80, pdf.bounds.width - 366 ]
        )
        pdf.move_down 16
      end

      def draw_invoices(pdf)
        rows = [ [ "Invoice", "Booking", "Issued", "Due", "Status", "Amount", "Outstanding" ] ]
        rows.concat(@invoices.map do |invoice|
          [
            invoice.formatted_invoice_number,
            invoice.booking.confirmation_token,
            invoice.issued_on.to_s,
            invoice.due_on.to_s,
            invoice.status.humanize,
            money(invoice.amount),
            money(invoice.outstanding_amount)
          ]
        end)
        rows << [ { content: "TOTAL (#{@currency})", colspan: 5, align: :right, font_style: :bold }, { content: money(@invoices.sum(&:amount)), align: :right, font_style: :bold }, { content: money(@invoices.sum(&:outstanding_amount)), align: :right, font_style: :bold } ]

        pdf.table(rows, header: true, width: pdf.bounds.width, cell_style: { size: 8, padding: [ 6, 4 ], border_color: "e5e7eb" }) do
          row(0).font_style = :bold
          row(0).background_color = "f3f4f6"
          columns(5..6).align = :right
        end
      end

      def draw_footer(pdf)
        printed = @printed_by.present? ? " · Printed by #{@printed_by}" : ""
        pdf.number_pages(
          "Generated #{Time.current.strftime('%Y-%m-%d %H:%M')}#{printed} · Page <page> of <total>",
          at: [ pdf.bounds.left, -30 ],
          width: pdf.bounds.width,
          align: :center,
          size: 8,
          color: "6b7280"
        )
      end

      def money(amount)
        Kernel.format("%.2f", amount.to_d)
      end
    end
  end
end
