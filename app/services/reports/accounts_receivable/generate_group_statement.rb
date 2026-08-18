# frozen_string_literal: true

module Reports
  module AccountsReceivable
    class GenerateGroupStatement
      ValidationError = Class.new(StandardError)
      Exports = HotelPortal::Reports::Exports

      def initialize(hotel:, group_booking:, hotel_corporate_account:, currency:, printed_by: nil)
        @hotel = hotel
        @group_booking = group_booking
        @hotel_corporate_account = hotel_corporate_account
        @currency = currency.to_s
        @printed_by = printed_by.presence || "-"
      end

      def generate
        validate_and_load!
        generated_at = Time.current
        builder = Exports::PdfReportBuilder.new(
          hotel: @hotel,
          title: "Group Accounts Receivable Statement",
          subtitle: @group_booking.formatted_reservation_number.to_s,
          period_label: nil,
          prepared_by: @printed_by,
          metadata: metadata(generated_at),
          generated_at: generated_at,
          page_layout: :landscape,
          confidential: false
        )
        builder.add_header
        add_invoices(builder)
        builder.render
      end

      private

      def validate_and_load!
        raise ValidationError, "Booking group must belong to this hotel." unless @group_booking.hotel_id == @hotel.id
        unless @hotel_corporate_account.hotel_id == @hotel.id
          raise ValidationError, "Corporate account must belong to this hotel."
        end
        raise ValidationError, "Currency is required." if @currency.blank?

        @invoices = @hotel.ar_invoices
          .includes(:hotel, { hotel_corporate_account: :corporate_account }, booking_folio: :booking)
          .joins(booking_folio: :booking)
          .where(
            hotel_corporate_account: @hotel_corporate_account,
            currency: @currency,
            bookings: { group_booking_id: @group_booking.id }
          )
          .where.not(status: "void")
          .order(:issued_on, :id)
          .to_a
        raise ValidationError, "No AR invoices are available for this payer and currency." if @invoices.empty?

        @account = @invoices.first.corporate_account
      end

      def metadata(generated_at)
        [
          [ "Corporate account", @account.name ],
          [ "Currency", @currency ],
          [ "Invoices", @invoices.size.to_s ],
          [ "Generated", Exports::PdfTheme.format_time(generated_at, @hotel.hotel_time_zone) ],
          [ "Prepared by", @printed_by ]
        ]
      end

      def add_invoices(builder)
        builder.add_table(
          section_title: "Group Invoices",
          headers: [ "Invoice", "Booking", "Issued", "Due", "Status", "Amount", "Outstanding" ],
          rows: @invoices.map { |invoice| invoice_row(invoice) },
          numeric_columns: [ 5, 6 ],
          total_row: [
            { content: "TOTAL (#{@currency})", colspan: 5, align: :right },
            money(@invoices.sum(&:amount)),
            money(@invoices.sum(&:outstanding_amount))
          ],
          empty_message: "No group invoices are available.",
          column_widths: proportional_widths(builder.content_width, [ 15, 18, 11, 11, 11, 17, 17 ])
        )
      end

      def invoice_row(invoice)
        [
          invoice.formatted_invoice_number,
          invoice.booking.confirmation_token,
          Exports::PdfTheme.format_date(invoice.issued_on),
          Exports::PdfTheme.format_date(invoice.due_on),
          invoice.status.humanize,
          money(invoice.amount),
          money(invoice.outstanding_amount)
        ]
      end

      def proportional_widths(width, shares)
        widths = shares.map { |share| width * share / shares.sum.to_f }
        widths[-1] += width - widths.sum
        widths
      end

      def money(amount) = Exports::PdfTheme.money(amount)
    end
  end
end
