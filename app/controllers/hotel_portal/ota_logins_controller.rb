# frozen_string_literal: true

module HotelPortal
  class OtaLoginsController < SettingsBaseController
    include SheetActionCompletion

    before_action :authorize!

    def new
      @credential = current_hotel.hotel_ota_credentials.build
      render layout: false
    end

    def create
      result = OtaLogins::Create.call(hotel: current_hotel, attributes: credential_params)
      @credential = result.credential

      if result.success?
        complete_sheet_action(
          destination: hotel_ota_logins_settings_path(current_hotel),
          notice: "OTA login added.",
          frame: turbo_frame_request_id.presence || "settings_action_sheet"
        )
      else
        @password_typed = @credential.password.present?
        @credential.password = nil
        render :new, formats: :html, layout: false, status: :unprocessable_content
      end
    end

    private

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def credential_params
      params.require(:hotel_ota_credential).permit(
        :channel_name, :property_code, :username, :password,
        :market_manager_name, :market_manager_phone, :market_manager_email
      )
    end
  end
end
