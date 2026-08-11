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
  before_validation :set_default_max_children
  after_create :ensure_system_rate_plans

  validates :name, presence: true
  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_adults, presence: true, numericality: { greater_than: 0 }
  validates :max_children, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :base_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :room_number_mode, presence: true, inclusion: { in: %w[range custom] }
  validate :amenities_must_be_from_list

  def room_numbers
    Array(super).flatten.compact.map(&:to_s).reject(&:blank?)
  end

  def max_capacity
    max_adults.to_i + max_children.to_i
  end

  # The plan that anchors this category's pricing: the one EnsureSystemPlans
  # creates alongside the category, the row the pricing rules write to, and the
  # plan every booking path falls back to when no rate was picked.
  #
  # This is the single answer to "which plan is Standard here". Resolving it two
  # ways — this method for pricing and restrictions, an active-scoped find_by for
  # bookings — let the two disagree the moment a category held more than one.
  #
  # Falls back to the oldest active plan for categories that predate the kind
  # column and whose anchor was renamed to something the backfill did not
  # recognise; that plan was created with the category, so it still sorts first.
  # The fallback is oldest-first, unlike system_rate_plan below — there is no
  # dedicated plan to prefer, so the category's original plan is the best guess.
  def standard_rate_plan
    return @standard_rate_plan if defined?(@standard_rate_plan)

    @standard_rate_plan = system_rate_plan("standard") || active_rate_plans.first
  end

  def walk_in_rate_plan
    system_rate_plan("walk_in")
  end

  def corporate_rate_plan
    system_rate_plan("corporate")
  end

  # Newest wins. EnsureSystemPlans deliberately leaves a shared legacy plan
  # attached for historical use and creates a dedicated one alongside it, so the
  # plan created for this category is always the later id and must be the one
  # that answers here.
  def system_rate_plan(kind)
    active_rate_plans.select { |plan| plan.kind == kind.to_s }.max_by(&:id)
  end

  # Which plan's rows carry the restrictions in force for a given plan. Walk-in
  # and corporate price their own nights but do not close them: stop-sell and
  # CTA/CTD belong to the night, so they are read off the anchor.
  def restriction_plan_for(rate_plan)
    rate_plan&.anchored? ? standard_rate_plan : rate_plan
  end

  # Anything that attaches or archives a plan for this category has to call this,
  # or the memo above keeps answering from the plan set as it was. EnsureSystemPlans
  # resolves the anchor while it is still building the category, so without a reset
  # it would memoize "no standard plan" and hand that to every later caller.
  def reset_rate_plan_cache!
    remove_instance_variable(:@standard_rate_plan) if defined?(@standard_rate_plan)
    remove_instance_variable(:@active_rate_plans) if defined?(@active_rate_plans)
    rate_plans.reset
    room_type_rate_plans.reset
    self
  end

  # reload clears the association cache but not the memos built from it, which
  # would otherwise keep answering with the plan set as it was before the reload.
  def reload(*)
    super.tap { reset_rate_plan_cache! }
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

  def set_default_max_children
    self.max_children = 0 if max_children.nil?
  end

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

  # Sorted oldest-first so callers can pick either end deterministically.
  # Resolved in Ruby rather than through a scope so a preloaded :rate_plans
  # association is used as-is — AvailabilityService and the rates calendar both
  # preload it and would otherwise pay a query per category.
  def active_rate_plans
    @active_rate_plans ||= rate_plans.reject(&:archived?).sort_by(&:id)
  end

  def ensure_system_rate_plans
    RatePlans::EnsureSystemPlans.call!(room_type: self)
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
