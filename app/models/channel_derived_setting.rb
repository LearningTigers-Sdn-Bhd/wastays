# frozen_string_literal: true

class ChannelDerivedSetting < ApplicationRecord
  belongs_to :hotel

  validates :channel_id, presence: true
  validates :pricing_mode, presence: true, inclusion: { in: %w[same multiplier offset] }
  validates :pricing_value, numericality: { greater_than_or_equal_to: -100 }, allow_nil: true
  validates :room_allocation_mode, presence: true, inclusion: { in: %w[shared custom] }
  validates :room_allocation_value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Hook to sync updates with the channel manager if required
  after_commit :trigger_derived_rates_sync, on: [ :create, :update ]

  def trigger_derived_rates_sync
    return if Thread.current[:skip_ari_sync]
    return if hotel.preferred_channel_manager.blank?

    # 1. Sync rates & availability for the immediate 30-day window synchronously for instant feedback
    ChannelManagers::SyncJob.perform_now(
      hotel.id,
      Date.current,
      Date.current + 30.days,
      sync_availability: true,
      sync_rates: true,
      sync_restrictions: false
    )

    # 2. Sync the remaining window (days 31 to 499) in the background
    ChannelManagers::SyncJob.perform_later(
      hotel.id,
      Date.current + 31.days,
      Date.current + 499.days,
      sync_availability: true,
      sync_rates: true,
      sync_restrictions: false
    )
  end
end
