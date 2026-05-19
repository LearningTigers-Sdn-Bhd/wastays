module HotelPortal
  class SettingsController < HotelPortal::BaseController
    SETTINGS_TABS = %w[general tax ai notifications banking].freeze

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
        redirect_to hotel_settings_path(@hotel, tab: @active_settings_tab), alert: "Payment gateway credentials are managed by superadmin."
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
      @property_policy = @hotel&.property_policy
      @property_policy ||= @hotel&.build_property_policy if action_name.in?(%w[index edit])
    end

    def load_settings
      @active_settings_tab = active_settings_tab

      if @hotel
        @property_policy ||= @hotel.property_policy || @hotel.build_property_policy

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

        @check_out_receipt_notification_config = NotificationConfig.find_or_initialize_by(
          hotel: @hotel,
          notification_type: "check_out_receipt_message"
        )
        @check_out_receipt_notification_config.enabled = false if @check_out_receipt_notification_config.new_record?
        @check_out_receipt_notification_config.channels = [ "whatsapp", "email" ] if @check_out_receipt_notification_config.channels.blank?

        @in_stay_guest_notification_config = NotificationConfig.find_or_initialize_by(
          hotel: @hotel,
          notification_type: "in_stay_guest_messaging"
        )
        @in_stay_guest_notification_config.enabled = false if @in_stay_guest_notification_config.new_record?
        @in_stay_guest_notification_config.channels = [ "whatsapp", "email" ] if @in_stay_guest_notification_config.channels.blank?
        @in_stay_guest_notification_config.settings = @in_stay_guest_notification_config.settings.to_h.reverse_merge(
          "rules" => {
            "mid_stay" => { "enabled" => true, "time" => "12:00" },
            "upsell" => { "enabled" => true, "time" => "17:00" },
            "activity" => { "enabled" => true, "time" => "10:00" }
          },
          "quiet_hours" => { "enabled" => true, "start" => "22:00", "end" => "08:00" }
        )

        @settings = {
          hotel_status: @hotel.status.humanize,
          onboarding_stage: onboarding_stage(@hotel),
          check_in: @property_policy&.check_in_time,
          check_out: @property_policy&.check_out_time,
          default_currency: @hotel.default_currency,
          tourism_tax_enabled: @hotel.tourism_tax_enabled?,
          tourism_tax_amount: @hotel.tourism_tax_amount,
          sst_enabled: @hotel.sst_enabled?
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

      if ai_configuration_form?
        update_ai_configuration!
        return redirect_to hotel_settings_path(@hotel, tab: "ai"), notice: "Settings updated successfully."
      end

      ActiveRecord::Base.transaction do
        @hotel.update!(hotel_params)

        if should_update_property_policy?
          # In some update flows Rails can leave the previously memoized association frozen.
          # Always write through a fresh mutable instance.
          policy = fresh_property_policy
          policy.update!(property_policy_params)
        end
      end

      redirect_to hotel_settings_path(@hotel, tab: settings_tab_for_form), notice: "Settings updated successfully."
    rescue ActiveRecord::RecordInvalid, FrozenError
      load_settings
      @account.build_banking_detail unless @account.banking_detail
      render :index, status: :unprocessable_entity
    end

    def update_banking_details
      authorize_banking_details_update!

      if @account.update(account_params)
        redirect_to hotel_settings_path(@hotel, tab: "banking"), notice: "Settings updated successfully."
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
        redirect_to hotel_settings_path(@hotel, tab: "notifications"), notice: "Settings updated successfully."
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
        :default_currency,
        :time_zone,
        :tourism_tax_enabled,
        :tourism_tax_amount,
        :sst_enabled,
        :ai_provider_enabled,
        :ai_concierge_tone,
        :ai_provider_name,
        :ai_provider_key,
        property_policy_attributes: [
          :id,
          :check_in_time,
          :check_out_time
        ]
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

    def ai_configuration_form?
      params[:form_id].to_s == "ai_configuration"
    end

    def update_ai_configuration!
      attrs = hotel_params.slice(:ai_provider_enabled, :ai_concierge_tone, :ai_provider_name, :ai_provider_key)
      enabled = ActiveModel::Type::Boolean.new.cast(attrs[:ai_provider_enabled])

      @hotel.assign_attributes(attrs)
      @hotel.errors.add(:ai_provider_name, "can't be blank") if enabled && @hotel.ai_provider_name.blank?
      @hotel.errors.add(:ai_provider_key, "can't be blank") if enabled && @hotel.ai_provider_key.blank?
      raise ActiveRecord::RecordInvalid, @hotel if @hotel.errors.any?

      # Avoid unrelated autosave association validation (property_policy) on AI-only updates.
      @hotel.save!(validate: false)
    end

    def should_update_property_policy?
      return false unless params[:form_id].to_s == "hotel_settings"

      attrs = params.dig(:hotel, :property_policy_attributes)
      return false if attrs.blank?

      attrs[:check_in_time].present? || attrs[:check_out_time].present?
    end

    def fresh_property_policy
      policy = @hotel.property_policy
      return @hotel.build_property_policy if policy.blank?

      policy.frozen? ? PropertyPolicy.find(policy.id) : policy
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
      when "in_stay_guest_messaging"
        raw_settings = params.require(:notification_config).permit(
          settings: {
            rules: {
              mid_stay: [ :enabled, :time ],
              upsell: [ :enabled, :time ],
              activity: [ :enabled, :time ]
            },
            quiet_hours: [ :enabled, :start, :end ]
          }
        ).fetch(:settings, {})

        rules = %w[mid_stay upsell activity].index_with do |rule_key|
          rule = raw_settings.fetch(:rules, {}).fetch(rule_key.to_sym, {})
          {
            "enabled" => ActiveModel::Type::Boolean.new.cast(rule[:enabled]),
            "time" => normalize_hhmm(rule[:time], default_time_for(rule_key))
          }
        end
        quiet = raw_settings.fetch(:quiet_hours, {})

        {
          "rules" => rules,
          "quiet_hours" => {
            "enabled" => ActiveModel::Type::Boolean.new.cast(quiet[:enabled]),
            "start" => normalize_hhmm(quiet[:start], "22:00"),
            "end" => normalize_hhmm(quiet[:end], "08:00")
          }
        }
      else
        {}
      end
    end

    def normalize_hhmm(raw, fallback)
      value = raw.to_s.strip
      return fallback unless /\A([01]\d|2[0-3]):[0-5]\d\z/.match?(value)

      value
    end

    def default_time_for(rule_key)
      {
        "mid_stay" => "12:00",
        "upsell" => "17:00",
        "activity" => "10:00"
      }.fetch(rule_key)
    end

    def settings_policy
      current_hotel.property_policy || current_hotel.build_property_policy
    end

    def active_settings_tab
      requested_tab = params[:tab].to_s
      return requested_tab if SETTINGS_TABS.include?(requested_tab)

      settings_tab_for_form
    end

    def settings_tab_for_form
      case params[:form_id].to_s
      when "hotel_settings"
        "general"
      when "tax_settings"
        "tax"
      when "ai_configuration"
        "ai"
      when "notification_settings"
        "notifications"
      else
        "general"
      end
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
