module HotelPortal
  class SettingsController < HotelPortal::BaseController
    before_action :set_account
    before_action :authorize_account_management!, only: :update

    def show
      load_settings
      @account.build_banking_detail unless @account.banking_detail
      render :index
    end

    def update
      load_settings
      @account.build_banking_detail unless @account.banking_detail

      if @account.update(account_params)
        redirect_to hotel_settings_path, notice: "Settings updated successfully."
      else
        render :index, status: :unprocessable_entity
      end
    end

    private

    def set_account
      @account = current_user.account
    end

    def load_settings
      if current_hotel
        policy = current_hotel.property_policy
        @settings = {
          hotel_status: current_hotel.status.humanize,
          onboarding_stage: onboarding_stage(current_hotel),
          check_in: policy&.check_in_time,
          check_out: policy&.check_out_time
        }
      else
        @settings = {}
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
