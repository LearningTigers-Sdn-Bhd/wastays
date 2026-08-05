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
  SPECIAL_TIER_KINDS = %w[walk_in corporate ota].freeze

  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :sell_mode, presence: true, inclusion: { in: %w[per_room per_person] }
  validate :pax_pricing_allowed_for_person_mode
  validate :sell_mode_matches_hotel_exclusivity
  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :single_supplement, numericality: { greater_than_or_equal_to: 0 }
  validates :child_price_multiplier, numericality: { greater_than_or_equal_to: 0 }
  validates :base_occupancy, numericality: { only_integer: true, greater_than: 0 }
  validates :extra_pax_charge, numericality: { greater_than_or_equal_to: 0 }

  before_validation :normalize_currency

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  after_commit :sync_with_channel_manager, on: [ :create, :update ]
  after_destroy_commit :delete_from_channel_manager, if: :synced_with_channel_manager?

  def self.sell_modes
    %w[per_room per_person]
  end

  def special_tier?
    kind.in?(SPECIAL_TIER_KINDS)
  end

  def standard_rate?
    kind == "standard"
  end

  def deletable?
    !special_tier? && !standard_rate? && !booking_rooms.exists?
  end

  def archived?
    archived_at.present?
  end

  # Standard Rate and special tiers (walk-in/corporate/ota) are structurally
  # required and must always stay bookable, so they can't be archived either.
  def archivable?
    !special_tier? && !standard_rate?
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

  def band_for_age(age)
    rate_plan_age_bands.find { |band| age.to_i.between?(band.min_age, band.max_age) }
  end

  # Symbol tier name for the pricing paths that key off it (rate_options,
  # build_financial_snapshot); nil for standard and custom plans.
  def special_tier_kind
    kind.to_sym if special_tier?
  end

  private

  def normalize_currency
    self.currency = CurrencyCatalog.normalize(currency)
  end

  def pax_pricing_allowed_for_person_mode
    if sell_mode == "per_person" && !hotel&.allow_pax_pricing?
      errors.add(:sell_mode, "cannot be set to Per Person unless allowed by admin")
    end
  end

  # Per-pax hotels sell exclusively to premium/package guests: once a hotel
  # is flipped to pax_pricing_only, its bookable rate plans cannot mix
  # per_room and per_person. Special tiers and standard plans are exempt
  # because they anchor data other parts of the system read regardless of
  # mode — room_rates.walk_in_price and .corporate_price for the tiers, and
  # the per-room-type base price for standard.
  def sell_mode_matches_hotel_exclusivity
    return unless hotel&.pax_pricing_only?
    return unless sell_mode == "per_room"
    return if special_tier? || standard_rate?

    errors.add(:sell_mode, "must be Per Person while this hotel is set to pax-pricing only")
  end

  def sync_with_channel_manager
    return if hotel.preferred_channel_manager.blank?
    return if sell_mode == "per_person"

    ChannelManagers::SyncStructureJob.perform_later(self.class.name, id, "sync")
  end

  def delete_from_channel_manager
    ChannelManagers::SyncStructureJob.perform_later(self.class.name, nil, "delete", hotel_id: hotel_id, external_id: channel_mapping.external_id)
  end

  def synced_with_channel_manager?
    hotel.preferred_channel_manager.present? && channel_mapping.present? && !channel_mapping.external_id.to_s.start_with?("pending")
  end
end
