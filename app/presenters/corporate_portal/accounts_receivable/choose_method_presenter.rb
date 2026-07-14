# frozen_string_literal: true

module CorporatePortal
  module AccountsReceivable
    class ChooseMethodPresenter
      attr_reader :account, :hotel_corporate_account_id

      def initialize(account:, hotel_corporate_account_id:, invoice_ids:)
        @account = account
        @hotel_corporate_account_id = hotel_corporate_account_id
        @invoice_ids = Array(invoice_ids).reject(&:blank?)
      end

      def relationship
        @relationship ||= HotelCorporateAccount.where(corporate_account_id: account.id, status: "active").includes(:hotel).find_by(id: hotel_corporate_account_id)
      end

      def invoices
        @invoices ||= begin
          return ArInvoice.none if relationship.blank? || @invoice_ids.empty?

          relationship.hotel.ar_invoices
            .with_open_balance
            .where(hotel_corporate_account: relationship, id: @invoice_ids)
            .includes(booking_folio: :booking)
            .order(due_on: :asc, invoice_number: :asc)
        end
      end

      def currency
        invoices.first&.currency
      end

      def total_amount
        invoices.sum(:outstanding_amount)
      end

      def gateway_ready?
        relationship&.hotel&.effective_payment_setting("razorpay").present?
      end
    end
  end
end
