module HotelPortal
  class SettingsController < HotelPortal::BaseController
    def index
      return @settings = {} unless current_hotel

      policy = settings_policy
      @settings = {
        hotel_status: current_hotel.status.humanize,
        onboarding_stage: onboarding_stage(current_hotel),
        check_in: policy.check_in_time.presence || "Not set",
        check_out: policy.check_out_time.presence || "Not set",
        currency: policy.currency.presence || "MYR",
        usd_rate: policy.usd_rate.presence || 0.21,
        tourism_tax: 10.00
      }
    end

    def edit
      @property_policy = settings_policy
    end

    def update
      @property_policy = settings_policy

      if @property_policy.update(settings_params)
        redirect_to hotel_settings_path, notice: "Settings updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def authorize_account_management!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_account")
    end

    def account_params
      params.require(:account).permit(
        banking_detail_attributes: [
          :id,
          :account_holder_name,
          :bank_name,
          :account_number,
          :account_type
        ]
      )
    end

    def settings_policy
      current_hotel.property_policy || current_hotel.build_property_policy(currency: "MYR", usd_rate: 0.21)
    end

    def settings_params
      params.require(:property_policy).permit(:check_in_time, :check_out_time, :currency, :usd_rate)
    end

    def onboarding_stage(hotel)
      if hotel.status == "live"
        "Live"
      elsif hotel.status == "pending_review"
        "Pending Review"
      else
        "Building profile"
      end
    end
  end
end
