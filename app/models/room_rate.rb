class RoomRate < ApplicationRecord
  belongs_to :room_type
  belongs_to :rate_plan, optional: true

  validates :date, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :date, uniqueness: { scope: :rate_plan_id }

  after_commit :trigger_ari_sync, on: [ :create, :update ]

  private

  def trigger_ari_sync
    return if room_type.hotel.preferred_channel_manager.blank?

    ChannelManagers::BufferAriSyncJob.perform_later(room_type.hotel_id, date)
  end
end
