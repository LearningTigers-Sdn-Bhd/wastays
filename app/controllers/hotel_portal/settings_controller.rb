module HotelPortal
  class SettingsController < HotelPortal::BaseController
    before_action :set_account
    before_action :set_hotel
    before_action :set_payment_setting, only: [ :index, :update ]

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

      if settings_update_request?
        update_settings
      elsif payment_setting_update_request?
        update_payment_setting
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

    def set_payment_setting
      selected_gateway = params.dig(:payment_setting, :gateway).presence || @hotel&.checkout_payment_gateway || "razorpay"
      @payment_setting = @hotel&.payment_settings&.find_or_initialize_by(gateway: selected_gateway)
      @payment_setting.status ||= "active" if @payment_setting
    end

    def load_settings
      if @hotel
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

    def payment_setting_update_request?
      params[:payment_setting].present?
    end

    def update_settings
      authorize_settings_update!

      ActiveRecord::Base.transaction do
        @hotel.update!(hotel_params)
        @property_policy ||= @hotel.property_policy || @hotel.build_property_policy
        @property_policy.update!(property_policy_params)
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

    def update_payment_setting
      authorize_settings_update!

      gateway = payment_setting_params[:gateway].to_s.downcase
      @payment_setting = @hotel.payment_settings.find_or_initialize_by(gateway: gateway)
      attrs = payment_setting_params.merge(gateway: gateway)
      attrs[:api_key] = @payment_setting.api_key if attrs[:api_key].blank?
      attrs[:secret_key] = @payment_setting.secret_key if attrs[:secret_key].blank?
      attrs[:webhook_secret] = @payment_setting.webhook_secret if attrs[:webhook_secret].blank?

      if @payment_setting.update(attrs)
        redirect_to hotel_settings_path(@hotel), notice: "Payment gateway configuration updated successfully."
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
        :tourism_tax_amount
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

    def payment_setting_params
      params.require(:payment_setting).permit(
        :gateway,
        :api_key,
        :secret_key,
        :webhook_secret,
        :status
      )
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
