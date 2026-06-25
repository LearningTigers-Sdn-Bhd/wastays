# frozen_string_literal: true

module HotelPortal
  module ArPayments
    class ShowPresenter
      AllocationRow = Struct.new(
        :allocation, :invoice_label, :invoice_path, :allocated_amount, :allocated_at,
        :reversed, :reversal_reason, :reversed_by, :reversed_at,
        keyword_init: true
      )

      attr_reader :payment, :hotel

      def initialize(payment:, hotel:, can_manage:)
        @payment = payment
        @hotel = hotel
        @can_manage = can_manage
      end

      def reference
        payment.reference_number
      end

      def company_name
        payment.corporate_account.name
      end

      def amount_label
        money(payment.amount)
      end

      def allocated_amount_label
        money(allocated_amount)
      end

      def unapplied_amount_label
        money(unapplied_amount_value)
      end

      def status_label
        allocation_status.humanize
      end

      def status_class
        case allocation_status
        when "unapplied" then "border-red-200 bg-red-50 text-red-700"
        when "partially_allocated" then "border-amber-200 bg-amber-50 text-amber-700"
        else "border-emerald-200 bg-emerald-50 text-emerald-700"
        end
      end

      def received_on
        payment.received_at.strftime("%d %b %Y")
      end

      def payment_method
        payment.payment_method.humanize
      end

      def recorded_at
        payment.created_at.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y, %I:%M %p")
      end

      def notes
        payment.notes.presence || "—"
      end

      def can_manage?
        @can_manage
      end

      def can_allocate?
        can_manage? && unapplied_amount_value.positive? && eligible_invoices.any?
      end

      def unapplied_amount_value
        payment.amount.to_d - allocated_amount
      end

      def allocation_rows
        @allocation_rows ||= payment.ar_payment_allocations
          .sort_by(&:created_at)
          .reverse
          .map do |allocation|
            reversal = allocation.reversal
            AllocationRow.new(
              allocation: allocation,
              invoice_label: "AR-#{allocation.ar_invoice.invoice_number}",
              invoice_path: Rails.application.routes.url_helpers.hotel_ar_invoice_path(hotel, allocation.ar_invoice),
              allocated_amount: money(allocation.amount),
              allocated_at: allocation.created_at.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y, %I:%M %p"),
              reversed: reversal.present?,
              reversal_reason: reversal&.reason,
              reversed_by: reversal&.reversed_by&.name,
              reversed_at: reversal&.reversed_at&.in_time_zone(hotel.hotel_time_zone)&.strftime("%d %b %Y, %I:%M %p")
            )
          end
      end

      def eligible_invoices
        @eligible_invoices ||= hotel.ar_invoices
          .with_open_balance
          .where(hotel_corporate_account: payment.hotel_corporate_account, currency: payment.currency)
          .includes(booking_folio: :booking)
          .order(due_on: :asc, invoice_number: :asc)
      end

      private

      def allocated_amount
        @allocated_amount ||= payment.ar_payment_allocations.reject(&:reversed?).sum { |allocation| allocation.amount.to_d }
      end

      def allocation_status
        return "unapplied" if allocated_amount.zero?
        return "fully_allocated" if unapplied_amount_value.zero?

        "partially_allocated"
      end

      def money(amount)
        "#{payment.currency} #{format('%.2f', amount.to_d)}"
      end
    end
  end
end
