class RatePlan < ApplicationRecord
  include HotelScopable

  has_many :room_type_rate_plans, dependent: :destroy
  has_many :room_types, through: :room_type_rate_plans
  has_many :room_rates, dependent: :destroy
  has_many :channel_room_rates, dependent: :destroy
  has_many :booking_rooms, dependent: :restrict_with_error
  has_many :rate_plan_age_bands, -> { order(:position, :min_age) }, dependent: :destroy
  has_one :channel_mapping, as: :mappable, dependent: :destroy

  accepts_nested_attributes_for :rate_plan_age_bands, allow_destroy: true, reject_if: :all_blank

  KINDS = %w[standard walk_in corporate ota custom].freeze

  # Who may be sold each kind. Walk-in is front-desk only; corporate needs a
  # negotiated relationship; ota is distribution-only and sold by nobody here.
  # Every caller that filters plans by audience reads this rather than spelling
  # the list out — they drifted apart the last time they were written by hand.
  AUDIENCE_KINDS = {
    public: %w[standard custom],
    corporate: %w[standard custom corporate],
    staff: %w[standard custom walk_in corporate]
  }.freeze

  # Kinds a channel manager may carry. Not an audience: ota exists only to be
  # distributed, and walk-in/corporate must never leave the property.
  DISTRIBUTABLE_KINDS = %w[standard custom ota].freeze

  # Kinds that carry their own price but read restrictions off the category's
  # standard plan — stop-sell and CTA/CTD are properties of the night, not of
  # which desk sold it.
  ANCHORED_KINDS = %w[walk_in corporate].freeze

  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :sell_mode, presence: true, inclusion: { in: %w[per_room per_person] }
  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :single_supplement, numericality: { greater_than_or_equal_to: 0 }
  validates :child_price_multiplier, numericality: { greater_than_or_equal_to: 0 }
  validates :base_occupancy, numericality: { only_integer: true, greater_than: 0 }
  validates :extra_pax_charge, numericality: { greater_than_or_equal_to: 0 }
  validates :channex_children_fee, :channex_infant_fee,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :normalize_currency
  before_validation :inherit_sell_mode_from_hotel

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :for_audience, ->(audience) { active.where(kind: RatePlan.kinds_for(audience)) }

  after_commit :sync_with_channel_manager, on: [ :create, :update ]
  after_destroy_commit :delete_from_channel_manager, if: :synced_with_channel_manager?

  def self.sell_modes
    %w[per_room per_person]
  end

  def self.kinds_for(audience)
    AUDIENCE_KINDS.fetch(audience.to_sym)
  end

  def standard_rate?
    kind == "standard"
  end

  # Only a hotelier-created plan is deletable; every other kind is structural.
  def deletable?
    kind == "custom" && !booking_rooms.exists?
  end

  def anchored?
    kind.in?(ANCHORED_KINDS)
  end

  def bookable_by?(audience)
    !archived? && kind.in?(self.class.kinds_for(audience))
  end

  def archived?
    archived_at.present?
  end

  # Walk-in and Corporate can be archived — nothing else reads their rows. The
  # Standard plan cannot: it is the price anchor every other plan resolves
  # against, the restriction row walk-in/corporate read, and the only plan the
  # booking paths fall back to. Archiving it leaves the room category unsellable.
  def archivable?
    !standard_rate?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def age_banded?
    sell_mode == "per_person" && rate_plan_age_bands.any?
  end

  def channex_capability(room_type: nil)
    ChannelManagers::ChannexRatePlanCapability.call(rate_plan: self, room_type: room_type)
  end

  def channex_syncable?(room_type: nil)
    channex_capability(room_type: room_type).supported?
  end

  def band_for_age(age)
    rate_plan_age_bands.find { |band| age.to_i.between?(band.min_age, band.max_age) }
  end

  private

  def normalize_currency
    self.currency = CurrencyCatalog.normalize(currency)
  end

  # The hotel decides how it sells; a rate plan only decides how much. Nothing
  # writes sell_mode directly any more — not the rate plan sheet, not the
  # callers that create Standard plans — so this is the single point where the
  # value is set, on create and on every update.
  def inherit_sell_mode_from_hotel
    self.sell_mode = hotel.sell_mode if hotel
  end

  def sync_with_channel_manager
    return if Thread.current[:skip_ari_sync]
    return if hotel.preferred_channel_manager.blank?
    room_ids = room_type_rate_plans.pluck(:room_type_id)
    return if room_ids.empty?

    ChannelManagers::SyncRatePlanAri.call(rate_plan: self, room_type_ids: room_ids)
  end

  def delete_from_channel_manager
    ChannelManagers::SyncStructureJob.perform_later(self.class.name, nil, "delete", hotel_id: hotel_id, external_id: channel_mapping.external_id)
  end

  def synced_with_channel_manager?
    hotel.preferred_channel_manager.present? && channel_mapping.present? && !channel_mapping.external_id.to_s.start_with?("pending")
  end
end
