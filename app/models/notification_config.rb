# frozen_string_literal: true

class NotificationConfig < ApplicationRecord
  NOTIFICATION_TYPES = %w[check_in_confirmation post_stay_review_request].freeze
  CHANNELS = %w[email whatsapp].freeze

  belongs_to :hotel

  validates :notification_type, presence: true, inclusion: { in: NOTIFICATION_TYPES }
  validates :enabled, inclusion: { in: [ true, false ] }
  validates :channels, presence: true
  validate :channels_are_supported

  private

  def channels_are_supported
    unsupported = Array(channels).map(&:to_s) - CHANNELS
    errors.add(:channels, "contains unsupported values") if unsupported.any?
  end
end
