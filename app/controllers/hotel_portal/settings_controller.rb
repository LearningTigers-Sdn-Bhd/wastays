module HotelPortal
  class SettingsController < HotelPortal::BaseController
    before_action :set_account
    before_action :set_hotel

    def index
      load_settings
      @account.build_banking_detail unless @account.banking_detail
    end

    def edit
      @property_policy = settings_policy
    end

    def update
      load_settings
      @account.build_banking_detail unless @account.banking_detail

      if notification_update_request?
        update_notification_settings
      elsif settings_update_request?
        update_settings
      elsif params[:payment_setting].present?
        redirect_to hotel_settings_path(@hotel), alert: "Payment gateway credentials are managed by superadmin."
      else
        update_banking_details
      end
    end

    private

    def set_account
      @account = current_user.account
    end

    def set_hotel
      @hotel = current_hotel
      @property_policy = @hotel&.property_policy || @hotel&.build_property_policy
    end

    def load_settings
      if @hotel
        @notification_config = NotificationConfig.find_or_initialize_by(
          hotel: @hotel,
          notification_type: "check_in_confirmation"
        )
        @notification_config.enabled = true if @notification_config.new_record?
        @notification_config.channels = [ "whatsapp" ] if @notification_config.channels.blank?

        @settings = {
          hotel_status: @hotel.status.humanize,
          onboarding_stage: onboarding_stage(@hotel),
          check_in: @property_policy&.check_in_time,
          check_out: @property_policy&.check_out_time,
          default_currency: @hotel.default_currency,
          usd_conversion_rate: @hotel.usd_conversion_rate,
          tourism_tax_enabled: @hotel.tourism_tax_enabled?,
          tourism_tax_amount: @hotel.tourism_tax_amount
        }
      else
        @settings = {}
      end
    end

    def settings_update_request?
      params[:hotel].present?
    end

    def notification_update_request?
      params[:notification_config].present?
    end

    def update_settings
      authorize_settings_update!

      ActiveRecord::Base.transaction do
        @hotel.update!(hotel_params)

        if params.dig(:hotel, :property_policy_attributes).present?
          @property_policy ||= @hotel.property_policy || @hotel.build_property_policy
          @property_policy.update!(property_policy_params)
        end
      end

      redirect_to hotel_settings_path(@hotel), notice: "Settings updated successfully."
    rescue ActiveRecord::RecordInvalid
      load_settings
      @account.build_banking_detail unless @account.banking_detail
      render :index, status: :unprocessable_entity
    end

    def update_banking_details
      authorize_banking_details_update!

      if @account.update(account_params)
        redirect_to hotel_settings_path(@hotel), notice: "Settings updated successfully."
      else
        load_settings
        render :index, status: :unprocessable_entity
      end
    end

    def update_notification_settings
      authorize_settings_update!

      channels = Array(params.dig(:notification_config, :channels)).reject(&:blank?)
      @notification_config = NotificationConfig.find_or_initialize_by(
        hotel: @hotel,
        notification_type: "check_in_confirmation"
      )

      if @notification_config.update(notification_config_params.merge(channels: channels))
        redirect_to hotel_settings_path(@hotel), notice: "Settings updated successfully."
      else
        load_settings
        @account.build_banking_detail unless @account.banking_detail
        render :index, status: :unprocessable_entity
      end
    end

    def authorize_settings_update!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def authorize_banking_details_update!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_account")
    end

    def account_params
      params.require(:account).permit(
        banking_detail_attributes: [
          :id,
          :account_holder_name,
          :bank_name,
          :account_number
        ]
      )
    end

    def hotel_params
      params.require(:hotel).permit(
        :usd_conversion_rate,
        :tourism_tax_enabled,
        :tourism_tax_amount,
        :ai_provider_enabled,
        :ai_concierge_tone,
        :ai_provider_name,
        :ai_provider_key
      )
    end

    def property_policy_params
      params.require(:hotel).permit(
        property_policy_attributes: [
          :check_in_time,
          :check_out_time
        ]
      ).fetch(:property_policy_attributes)
    end

    def notification_config_params
      params.require(:notification_config).permit(:enabled)
    end

    def settings_policy
      current_hotel.property_policy || current_hotel.build_property_policy
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
