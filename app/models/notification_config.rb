# frozen_string_literal: true

class NotificationConfig < ApplicationRecord
  NOTIFICATION_TYPES = %w[
    check_in_confirmation
    post_stay_review_request
    pre_arrival_notification
    check_out_receipt_message
  ].freeze
  CHANNELS = %w[email whatsapp].freeze
  PRE_ARRIVAL_STAGES = %w[d2 d1].freeze

  belongs_to :hotel

  validates :notification_type, presence: true, inclusion: { in: NOTIFICATION_TYPES }
  validates :enabled, inclusion: { in: [ true, false ] }
  validates :channels, presence: true
  validate :channels_are_supported
  validate :pre_arrival_stages_are_supported

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
end
