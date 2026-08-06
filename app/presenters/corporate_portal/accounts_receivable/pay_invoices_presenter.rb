# frozen_string_literal: true

module CorporatePortal
  module AccountsReceivable
    class PayInvoicesPresenter
      attr_reader :account, :params

      def initialize(account:, params:)
        @account = account
        @params = params
      end

      def relationships
        @relationships ||= HotelCorporateAccount.where(corporate_account_id: account.id, status: "active")
          .includes(:hotel)
          .sort_by { |relationship| relationship.hotel.name.to_s.downcase }
      end

      def selected_relationship
        requested = params.dig(:corporate_ar_payment, :hotel_corporate_account_id).presence || params[:hotel_corporate_account_id].to_s
        @selected_relationship ||= relationships.find { |relationship| relationship.id.to_s == requested } || relationships.first
      end

      def selected_currency
        requested = params.dig(:corporate_ar_payment, :currency).presence || params[:currency].presence
        available_currencies.include?(requested) ? requested : available_currencies.first
      end

      def available_currencies
        @available_currencies ||= selected_relationship ? open_scope.distinct.order(:currency).pluck(:currency) : []
      end

      def invoices
        @invoices ||= begin
          return ArInvoice.none if selected_relationship.blank? || selected_currency.blank?

          open_scope.where(currency: selected_currency).includes(booking_folio: :booking).order(due_on: :asc, invoice_number: :asc)
        end
      end

      def gateway_ready?
        selected_relationship&.hotel&.effective_payment_setting("razorpay").present?
      end

      def default_amount
        invoices.sum(:outstanding_amount)
      end

      private

      def open_scope
        selected_relationship.hotel.ar_invoices.with_open_balance.where(hotel_corporate_account: selected_relationship)
      end
    end
  end
end
