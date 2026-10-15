# frozen_string_literal: true

module HotelPortal
  class CorporateAccountPasswordsController < FinancialsBaseController
    include SheetActionCompletion

    def show
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_corporate_accounts", hotel: current_hotel)

      relationship = current_hotel.hotel_corporate_accounts.includes(corporate_account: :users).find(params[:corporate_account_id])
      result = CorporateAccounts::RevealTemporaryPassword.call(relationship: relationship, hotel: current_hotel)
      raise ActiveRecord::RecordNotFound unless result.success?

      @credential_user = result.user
      @return_to = sheet_action_return_to(fallback: hotel_corporate_accounts_path(current_hotel))
      response.headers["Cache-Control"] = "no-store"
      render layout: false
    end
  end
end
