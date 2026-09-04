# frozen_string_literal: true

module CorporatePortal
  class ProfilesController < CorporatePortal::BaseController
    def show
      @account = current_user.account
      @relationships = corporate_relationships.includes(:hotel).order(created_at: :desc)
      @billing_addresses = @relationships.index_with do |relationship|
        CorporateAccounts::BillingAddressPresenter.new(relationship)
      end
    end
  end
end
