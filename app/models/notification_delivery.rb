# frozen_string_literal: true

class NotificationDelivery < ApplicationRecord
  # The extras are sent on demand -- by staff, or by an event in the agent
  # payment path -- rather than from a NotificationConfig schedule, so they have
  # no counterpart in the configurable set.
  EXTRA_NOTIFICATION_TYPES = %w[
    invoice_package
    guest_registration_card
    agent_payment_approved
    agent_payment_rejected
    agent_booking_released
  ].freeze
  NOTIFICATION_TYPES = (NotificationConfig::NOTIFICATION_TYPES + EXTRA_NOTIFICATION_TYPES).freeze
  CHANNELS = NotificationConfig::CHANNELS
  STATUSES = %w[pending sent failed skipped].freeze

  belongs_to :hotel
  belongs_to :booking

  validates :notification_type, presence: true, inclusion: { in: NOTIFICATION_TYPES }
  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :trigger_event, :idempotency_key, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :idempotency_key, uniqueness: true
end
