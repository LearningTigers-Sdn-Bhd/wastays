# frozen_string_literal: true

module HotelPortal
  class NotificationSettingsForm
    include ActiveModel::Model

    attr_reader :hotel, :params, :config

    def initialize(hotel, params)
      @hotel = hotel
      @params = params
    end

    def save
      channels = Array(params.dig(:notification_config, :channels)).reject(&:blank?)
      notification_type = params.dig(:notification_config, :notification_type).presence || "check_in_confirmation"

      @config = NotificationConfig.find_or_initialize_by(
        hotel: hotel,
        notification_type: notification_type
      )

      settings = build_notification_settings(notification_type)
      @config.update(notification_config_params.merge(channels: channels, settings: settings))
    end

    def errors
      @config&.errors || super
    end

    private

    def notification_config_params
      params.require(:notification_config).permit(:enabled)
    end

    def build_notification_settings(notification_type)
      case notification_type
      when "post_stay_review_request"
        build_review_settings
      when "pre_arrival_notification"
        build_pre_arrival_settings
      when "in_stay_guest_messaging"
        build_in_stay_settings
      else
        {}
      end
    end

    def build_review_settings
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
    end

    def build_pre_arrival_settings
      raw_settings = params.require(:notification_config).permit(settings: { stages: [] }).fetch(:settings, {})
      stages = Array(raw_settings[:stages]).map(&:to_s).select { |stage| stage.in?(%w[d2 d1]) }.uniq
      stages = %w[d2 d1] if stages.empty?

      { "stages" => stages }
    end

    def build_in_stay_settings
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
  end
end
