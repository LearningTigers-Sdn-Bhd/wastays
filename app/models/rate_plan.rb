class RatePlan < ApplicationRecord
  belongs_to :room_type
  has_many :room_rates, dependent: :destroy
  has_one :channel_mapping, as: :mappable, dependent: :destroy

  validates :name, presence: true
  validates :sell_mode, presence: true, inclusion: { in: %w[per_room per_person] }
  validates :currency, presence: true

  after_commit :sync_with_channel_manager, on: [ :create, :update ]
  after_destroy_commit :delete_from_channel_manager, if: :synced_with_channel_manager?

  def self.sell_modes
    %w[per_room per_person]
  end

  private

  def sync_with_channel_manager
    return if room_type.hotel.preferred_channel_manager.blank?

    ChannelManagers::SyncStructureJob.perform_later(self.class.name, id, "sync")
  end

  def delete_from_channel_manager
    ChannelManagers::SyncStructureJob.perform_later(self.class.name, nil, "delete", hotel_id: room_type.hotel_id, external_id: channel_mapping.external_id)
  end

  def synced_with_channel_manager?
    room_type.hotel.preferred_channel_manager.present? && channel_mapping.present? && channel_mapping.external_id != "pending"
  end
end
