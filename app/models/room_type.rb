# frozen_string_literal: true

class RoomType < ApplicationRecord
  include HotelScopable

  has_many :room_rates, dependent: :destroy
  has_many :room_inventories, dependent: :destroy
  has_many :rate_plans, dependent: :destroy
  has_many :inventory_audit_logs, dependent: :nullify
  has_many :booking_rooms, dependent: :restrict_with_error
  has_many :booking_quote_items, dependent: :restrict_with_error
  has_many :room_statuses, dependent: :destroy
  has_one :channel_mapping, as: :mappable, dependent: :destroy
  has_many_attached :photos

  MAX_PHOTOS = 10

  before_validation :set_default_room_number_mode, on: :create

  after_commit :sync_with_channel_manager, on: [ :create, :update ]
  after_destroy_commit :delete_from_channel_manager, if: :synced_with_channel_manager?

  validates :name, presence: true
  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_adults, presence: true, numericality: { greater_than: 0 }
  validates :base_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :room_number_mode, presence: true, inclusion: { in: %w[range custom] }
  validate :amenities_must_be_from_list

  def room_numbers
    Array(super).flatten.compact.map(&:to_s).reject(&:blank?)
  end

  def attach_photos_with_limit(photo_files)
    photo_files = Array(photo_files).reject(&:blank?)
    remaining_slots = [ MAX_PHOTOS - photos.count, 0 ].max
    photos_to_attach = photo_files.first(remaining_slots)

    photos.attach(photos_to_attach) if photos_to_attach.any?

    # Return summary for parity with Hotel model if needed
    {
      attached_count: photos_to_attach.size,
      trimmed_count: photo_files.size - photos_to_attach.size
    }
  end

  private

  def amenities_must_be_from_list
    return if amenities.blank?

    allowed_ids = Amenity.room.pluck(:slug)
    invalid_amenities = amenities - allowed_ids

    if invalid_amenities.any?
      errors.add(:amenities, "contains invalid options: #{invalid_amenities.join(', ')}")
    end
  end

  def set_default_room_number_mode
    self.room_number_mode = room_number_mode.presence || "range"
  end

  def sync_with_channel_manager
    return if hotel.preferred_channel_manager.blank?

    ChannelManagers::SyncStructureJob.perform_later(self.class.name, id, "sync")
  end

  def delete_from_channel_manager
    ChannelManagers::SyncStructureJob.perform_later(self.class.name, nil, "delete", hotel_id: hotel_id, external_id: channel_mapping.external_id)
  end

  def synced_with_channel_manager?
    hotel.preferred_channel_manager.present? && channel_mapping.present? && channel_mapping.external_id != "pending"
  end
end
