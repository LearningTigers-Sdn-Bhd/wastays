# frozen_string_literal: true

class ChannelAvailabilityRule < ApplicationRecord
  belongs_to :hotel

  validates :title, presence: true
  validates :start_date, presence: true
  validates :rule_type, presence: true, inclusion: { in: %w[close_out availability_offset max_availability] }
  validates :value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true


  after_commit :trigger_creation_or_update, on: [ :create, :update ]
  after_commit :trigger_deletion, on: [ :destroy ]

  private

  def trigger_creation_or_update
    return if Thread.current[:skip_ari_sync]
    return if hotel.preferred_channel_manager.blank?

    ChannelManagers::SyncAvailabilityRuleJob.perform_later(id, "sync")
  end

  def trigger_deletion
    return if Thread.current[:skip_ari_sync]
    return if hotel.preferred_channel_manager.blank?
    return if external_id.blank?

    ChannelManagers::SyncAvailabilityRuleJob.perform_later(nil, "delete", hotel_id: hotel_id, external_id: external_id)
  end
end
