# frozen_string_literal: true

module HotelPortal
  class SettingsPresenter
    PAGE_HEADINGS = {
      "general" => [ "General Settings", "Configure core hotel policies and operational defaults." ],
      "ai" => [ "AI Concierge", "Configure AI concierge behavior and provider settings." ],
      "notifications" => [ "Notifications", "Configure guest notification automations and channels." ],
      "banking" => [ "Banking Details", "Manage the bank account used for hotel payouts." ]
    }.freeze

    attr_reader :hotel, :active_page, :current_user

    def initialize(hotel:, active_page:, current_user:)
      @hotel = hotel
      @active_page = active_page
      @current_user = current_user
    end

    def property_policy
      @property_policy ||= hotel.property_policy || hotel.build_property_policy
    end

    def page_title
      PAGE_HEADINGS.fetch(active_page).first
    end

    def page_description
      PAGE_HEADINGS.fetch(active_page).last
    end

    def check_in_notification_config
      @check_in_notification_config ||= begin
        config = NotificationConfig.find_or_initialize_by(
          hotel: hotel,
          notification_type: "check_in_confirmation"
        )
        config.enabled = true if config.new_record?
        config.channels = [ "whatsapp" ] if config.channels.blank?
        config
      end
    end

    def post_stay_review_notification_config
      @post_stay_review_notification_config ||= begin
        config = NotificationConfig.find_or_initialize_by(
          hotel: hotel,
          notification_type: "post_stay_review_request"
        )
        config.enabled = false if config.new_record?
        config.channels = [ "whatsapp", "email" ] if config.channels.blank?
        config.settings = config.settings.to_h.reverse_merge(
          "review_link" => "",
          "send_delay_hours" => 2
        )
        config
      end
    end

    def pre_arrival_notification_config
      @pre_arrival_notification_config ||= begin
        config = NotificationConfig.find_or_initialize_by(
          hotel: hotel,
          notification_type: "pre_arrival_notification"
        )
        config.enabled = false if config.new_record?
        config.channels = [ "whatsapp", "email" ] if config.channels.blank?
        config.settings = config.settings.to_h.reverse_merge(
          "stages" => %w[d2 d1]
        )
        config
      end
    end

    def check_out_receipt_notification_config
      @check_out_receipt_notification_config ||= begin
        config = NotificationConfig.find_or_initialize_by(
          hotel: hotel,
          notification_type: "check_out_receipt_message"
        )
        config.enabled = false if config.new_record?
        config.channels = [ "whatsapp", "email" ] if config.channels.blank?
        config
      end
    end

    def in_stay_guest_notification_config
      @in_stay_guest_notification_config ||= begin
        config = NotificationConfig.find_or_initialize_by(
          hotel: hotel,
          notification_type: "in_stay_guest_messaging"
        )
        config.enabled = false if config.new_record?
        config.channels = [ "whatsapp", "email" ] if config.channels.blank?
        config.settings = config.settings.to_h.reverse_merge(
          "rules" => {
            "mid_stay" => { "enabled" => true, "time" => "12:00" },
            "upsell" => { "enabled" => true, "time" => "17:00" },
            "activity" => { "enabled" => true, "time" => "10:00" }
          },
          "quiet_hours" => { "enabled" => true, "start" => "22:00", "end" => "08:00" }
        )
        config
      end
    end

    def settings_summary
      return {} unless hotel

      {
        hotel_status: hotel.status.humanize,
        onboarding_stage: onboarding_stage,
        check_in: property_policy&.check_in_time,
        check_out: property_policy&.check_out_time,
        default_currency: hotel.default_currency
      }
    end

    def can_edit_currency?
      current_user.has_permission?("manage_hotel_profile")
    end

    def settings_errors
      hotel.errors.full_messages + property_policy.errors.full_messages
    end

    def time_picker_hours
      @time_picker_hours ||= (0..23).map do |h|
        {
          value: h,
          label: Time.current.change(hour: h).strftime("%I %p")
        }
      end
    end

    private

    def onboarding_stage
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
