# frozen_string_literal: true

module CorporatePortal
  class BaseController < ApplicationController
    include Breadcrumbable

    layout "corporate"

    before_action :authenticate_user!
    before_action :authenticate_corporate_user!

    helper CorporatePortal::NavigationHelper

    private

    def corporate_relationships
      current_user.account.hotel_corporate_accounts
    end

    def corporate_ar_invoices
      ArInvoice.joins(:hotel_corporate_account)
        .where(hotel_corporate_accounts: { corporate_account_id: current_user.account_id })
    end

    def corporate_ar_payments
      ArPayment.joins(:hotel_corporate_account)
        .where(hotel_corporate_accounts: { corporate_account_id: current_user.account_id })
    end

    def authenticate_corporate_user!
      return if current_user&.corporate? && current_user.account&.corporate?

      redirect_to root_path, alert: "You are not authorized to access the corporate portal."
    end
  end
end
