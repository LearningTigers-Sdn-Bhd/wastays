# frozen_string_literal: true

class NotificationDelivery < ApplicationRecord
  NOTIFICATION_TYPES = NotificationConfig::NOTIFICATION_TYPES
  CHANNELS = NotificationConfig::CHANNELS
  STATUSES = %w[pending sent failed].freeze

  belongs_to :hotel
  belongs_to :booking

  validates :notification_type, presence: true, inclusion: { in: NOTIFICATION_TYPES }
  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :trigger_event, :idempotency_key, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :idempotency_key, uniqueness: true
end
