class RoomInventory < ApplicationRecord
  belongs_to :room_type

  validates :date, presence: true
  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: %w[open closed] }
  validates :date, uniqueness: { scope: :room_type_id }

  scope :open, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }

  after_commit :trigger_ari_sync, on: [ :create, :update ]

  private

  def trigger_ari_sync
    return if room_type.hotel.preferred_channel_manager.blank?

    # Sync a window of 7 days around the changed date to be safe, or just the date
    ChannelManagers::SyncJob.perform_later(room_type.hotel_id, date, date)
  end
end
