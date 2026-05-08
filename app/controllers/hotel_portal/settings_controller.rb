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
        @check_in_notification_config = NotificationConfig.find_or_initialize_by(
          hotel: @hotel,
          notification_type: "check_in_confirmation"
        )
        @check_in_notification_config.enabled = true if @check_in_notification_config.new_record?
        @check_in_notification_config.channels = [ "whatsapp" ] if @check_in_notification_config.channels.blank?

        @post_stay_review_notification_config = NotificationConfig.find_or_initialize_by(
          hotel: @hotel,
          notification_type: "post_stay_review_request"
        )
        @post_stay_review_notification_config.enabled = false if @post_stay_review_notification_config.new_record?
        @post_stay_review_notification_config.channels = [ "whatsapp", "email" ] if @post_stay_review_notification_config.channels.blank?
        @post_stay_review_notification_config.settings = @post_stay_review_notification_config.settings.to_h.reverse_merge(
          "review_link" => "",
          "send_delay_hours" => 2
        )

        @pre_arrival_notification_config = NotificationConfig.find_or_initialize_by(
          hotel: @hotel,
          notification_type: "pre_arrival_notification"
        )
        @pre_arrival_notification_config.enabled = false if @pre_arrival_notification_config.new_record?
        @pre_arrival_notification_config.channels = [ "whatsapp", "email" ] if @pre_arrival_notification_config.channels.blank?
        @pre_arrival_notification_config.settings = @pre_arrival_notification_config.settings.to_h.reverse_merge(
          "stages" => %w[d2 d1]
        )

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
      notification_type = params.dig(:notification_config, :notification_type).presence || "check_in_confirmation"
      @notification_config = NotificationConfig.find_or_initialize_by(
        hotel: @hotel,
        notification_type: notification_type
      )
      settings = build_notification_settings(@notification_config.notification_type)

      if @notification_config.update(notification_config_params.merge(channels: channels, settings: settings))
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

    def build_notification_settings(notification_type)
      case notification_type
      when "post_stay_review_request"
        raw_settings = params.require(:notification_config).permit(settings: [ :review_link, :send_delay_hours ]).fetch(:settings, {})
        send_delay_hours_input = raw_settings[:send_delay_hours].to_s.strip
        send_delay_hours = if send_delay_hours_input.blank?
          2
        else
          parsed_delay = send_delay_hours_input.to_i
          parsed_delay.negative? ? 2 : parsed_delay
        end

        {
          "review_link" => raw_settings[:review_link].to_s.strip,
          "send_delay_hours" => send_delay_hours
        }
      when "pre_arrival_notification"
        raw_settings = params.require(:notification_config).permit(settings: { stages: [] }).fetch(:settings, {})
        stages = Array(raw_settings[:stages]).map(&:to_s).select { |stage| stage.in?(%w[d2 d1]) }.uniq
        stages = %w[d2 d1] if stages.empty?

        {
          "stages" => stages
        }
      else
        {}
      end
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
