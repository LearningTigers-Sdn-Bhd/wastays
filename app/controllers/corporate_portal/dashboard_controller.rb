# frozen_string_literal: true

module CorporatePortal
  class DashboardController < CorporatePortal::BaseController
    def index
      @relationships = current_user.account.hotel_corporate_accounts
        .active
        .includes(:hotel)
        .order(created_at: :desc)
      @outstanding_by_currency = corporate_ar_invoices.with_open_balance.group(:currency).sum(:outstanding_amount)
      @outstanding_by_relationship = corporate_ar_invoices
        .with_open_balance
        .group(:hotel_corporate_account_id)
        .sum(:outstanding_amount)
      # Rooms are released for non-payment, so what is owed on bookings is shown
      # apart from the AR balance above rather than folded into it.
      @payments = CorporatePortal::DashboardPaymentsPresenter.new(relation: corporate_bookings)
    end
  end
end
