# frozen_string_literal: true

class RoomType < ApplicationRecord
  include HotelScopable

  belongs_to :room_group, optional: true

  scope :unassigned, -> { where(room_group_id: nil) }

  has_many :room_rates, dependent: :destroy
  has_many :channel_room_rates, dependent: :destroy
  has_many :room_inventories, dependent: :destroy
  has_many :room_type_rate_plans, dependent: :destroy
  has_many :rate_plans, through: :room_type_rate_plans
  has_many :inventory_audit_logs, dependent: :nullify
  has_many :booking_rooms, dependent: :restrict_with_error
  has_many :booking_quote_items, dependent: :restrict_with_error
  has_many :room_statuses, dependent: :destroy
  has_one :channel_mapping, as: :mappable, dependent: :destroy
  has_many_attached :photos

  MAX_PHOTOS = 10

  before_validation :set_default_room_number_mode, on: :create
  after_create :ensure_standard_rate_plan

  validates :name, presence: true
  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_adults, presence: true, numericality: { greater_than: 0 }
  validates :base_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :room_number_mode, presence: true, inclusion: { in: %w[range custom] }
  validate :amenities_must_be_from_list

  def room_numbers
    Array(super).flatten.compact.map(&:to_s).reject(&:blank?)
  end

  def max_capacity
    max_adults.to_i + max_children.to_i
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

  def self.allowed_amenity_slugs
    @allowed_amenity_slugs ||= Amenity.room.pluck(:slug)
  end

  private

  def amenities_must_be_from_list
    return if amenities.blank?

    allowed_ids = self.class.allowed_amenity_slugs
    invalid_amenities = amenities - allowed_ids

    if invalid_amenities.any?
      errors.add(:amenities, "contains invalid options: #{invalid_amenities.join(', ')}")
    end
  end

  def set_default_room_number_mode
    self.room_number_mode = room_number_mode.presence || "range"
  end

  def ensure_standard_rate_plan
    return if rate_plans.exists?

    # Create a dedicated standard rate plan for this room type.
    #
    # Nightly prices would survive a shared plan — room_rates is unique on
    # (room_type_id, rate_plan_id, date, currency), so each room type keeps its
    # own price row either way. What does not survive is everything held on the
    # plan itself: sell_mode, currency, child_price_multiplier and the age
    # bands are single values, so a shared plan silently applies one room
    # type's rules to another, and leaves the second without a plan of its own
    # to edit.
    rate_plan = hotel.rate_plans.create!(
      name: "Standard Rate",
      kind: "standard",
      sell_mode: "per_room",
      currency: hotel.default_currency || "MYR"
    )

    room_type_rate_plans.create!(rate_plan: rate_plan)
  end

  def sync_with_channel_manager
    return if hotel.preferred_channel_manager.blank?

    ChannelManagers::SyncStructureJob.perform_later(self.class.name, id, "sync")
  end

  def delete_from_channel_manager
    ChannelManagers::SyncStructureJob.perform_later(self.class.name, nil, "delete", hotel_id: hotel_id, external_id: channel_mapping.external_id)
  end

  def synced_with_channel_manager?
    hotel.preferred_channel_manager.present? && channel_mapping.present? && !channel_mapping.external_id.to_s.start_with?("pending")
  end
end
