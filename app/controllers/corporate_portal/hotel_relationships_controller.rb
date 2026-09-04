# frozen_string_literal: true

module CorporatePortal
  class HotelRelationshipsController < CorporatePortal::BaseController
    before_action :set_relationship

    def edit
      @billing_address = CorporateAccounts::BillingAddressPresenter.new(@relationship)
    end

    def update
      if @relationship.update(relationship_params)
        redirect_to corporate_profile_path, notice: "Billing details for #{@relationship.hotel.name} updated."
      else
        @billing_address = CorporateAccounts::BillingAddressPresenter.new(@relationship)
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_relationship
      @relationship = current_user.account.hotel_corporate_accounts.includes(:hotel).find(params[:id])
    end

    def relationship_params
      params.require(:hotel_corporate_account).permit(
        :contact_email,
        :contact_phone,
        :billing_address_line1,
        :billing_address_line2,
        :billing_city,
        :billing_state,
        :billing_postal_code,
        :billing_country
      )
    end
  end
end
