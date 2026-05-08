# frozen_string_literal: true

class NotificationConfig < ApplicationRecord
  NOTIFICATION_TYPES = %w[
    check_in_confirmation
    post_stay_review_request
    pre_arrival_notification
    check_out_receipt_message
    in_stay_guest_messaging
  ].freeze
  CHANNELS = %w[email whatsapp].freeze
  PRE_ARRIVAL_STAGES = %w[d2 d1].freeze
  IN_STAY_RULE_KEYS = %w[mid_stay upsell activity].freeze

  belongs_to :hotel

  validates :notification_type, presence: true, inclusion: { in: NOTIFICATION_TYPES }
  validates :enabled, inclusion: { in: [ true, false ] }
  validates :channels, presence: true
  validate :channels_are_supported
  validate :pre_arrival_stages_are_supported
  validate :in_stay_settings_are_supported

  private

  def channels_are_supported
    unsupported = Array(channels).map(&:to_s) - CHANNELS
    errors.add(:channels, "contains unsupported values") if unsupported.any?
  end

  def pre_arrival_stages_are_supported
    return unless notification_type == "pre_arrival_notification"

    unsupported = Array(settings.to_h["stages"]).map(&:to_s) - PRE_ARRIVAL_STAGES
    errors.add(:settings, "contains unsupported pre-arrival stages") if unsupported.any?
  end

  def in_stay_settings_are_supported
    return unless notification_type == "in_stay_guest_messaging"

    raw_settings = settings.to_h
    rules = raw_settings.fetch("rules", {}).to_h
    unsupported_rules = rules.keys.map(&:to_s) - IN_STAY_RULE_KEYS
    errors.add(:settings, "contains unsupported in-stay rules") if unsupported_rules.any?

    rules.each do |rule_key, rule_settings|
      time = rule_settings.to_h["time"].to_s.strip
      next if time.blank? || valid_hhmm?(time)

      errors.add(:settings, "contains invalid time format for #{rule_key}")
    end

    quiet_hours = raw_settings.fetch("quiet_hours", {}).to_h
    %w[start end].each do |key|
      value = quiet_hours[key].to_s.strip
      next if value.blank? || valid_hhmm?(value)

      errors.add(:settings, "contains invalid quiet hour #{key} format")
    end
  end

  def valid_hhmm?(value)
    /\A([01]\d|2[0-3]):[0-5]\d\z/.match?(value)
  end
end
