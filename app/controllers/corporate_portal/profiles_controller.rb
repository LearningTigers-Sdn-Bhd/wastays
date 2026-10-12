# frozen_string_literal: true

module CorporatePortal
  class ProfilesController < CorporatePortal::BaseController
    def show
      prepare_profile
    end

    def update
      attributes = password_params
      current_user.errors.add(:password, "can't be blank") if attributes[:password].blank?
      if current_user.errors.empty? && Users::UpdateProfile.call(user: current_user, params: attributes)
        redirect_to corporate_profile_path, notice: "Password changed.", status: :see_other
      else
        prepare_profile
        render :show, status: :unprocessable_content
      end
    end

    private

    def password_params
      params.require(:user).permit(:current_password, :password, :password_confirmation)
    end

    def prepare_profile
      @account = current_user.account
      @relationships = corporate_relationships.includes(:hotel).order(created_at: :desc)
      @billing_addresses = @relationships.index_with do |relationship|
        CorporateAccounts::BillingAddressPresenter.new(relationship)
      end
    end
  end
end
