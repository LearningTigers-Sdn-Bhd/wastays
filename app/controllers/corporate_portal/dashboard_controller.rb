# frozen_string_literal: true

module CorporatePortal
  class DashboardController < CorporatePortal::BaseController
    def index
      @relationships = current_user.account.hotel_corporate_accounts
        .active
        .includes(:hotel)
        .order(created_at: :desc)
    end
  end
end
