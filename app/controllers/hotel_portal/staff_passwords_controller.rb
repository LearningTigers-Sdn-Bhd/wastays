# frozen_string_literal: true

module HotelPortal
  class StaffPasswordsController < SettingsBaseController
    def show
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_users", hotel: current_hotel)

      access = current_hotel.user_hotel_accesses.includes(:user).find(params[:user_id])
      result = StaffAccesses::RevealTemporaryPassword.call(access: access, hotel: current_hotel)
      raise ActiveRecord::RecordNotFound unless result.success?

      @credential_user = result.user
      response.headers["Cache-Control"] = "no-store"
      render layout: false
    end
  end
end
