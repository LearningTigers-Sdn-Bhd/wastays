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
    end
  end
end
