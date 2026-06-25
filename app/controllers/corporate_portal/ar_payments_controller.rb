# frozen_string_literal: true

module CorporatePortal
  class ArPaymentsController < CorporatePortal::BaseController
    def index
      @ar_payments = corporate_ar_payments
        .includes(:hotel, :ar_payment_allocations, hotel_corporate_account: :corporate_account)
        .order(received_at: :desc, created_at: :desc)
    end
  end
end
