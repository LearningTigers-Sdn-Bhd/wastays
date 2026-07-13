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

  validates :name, presence: true
  validates :sell_mode, presence: true, inclusion: { in: %w[per_room per_person] }
  validate :pax_pricing_allowed_for_person_mode
  validate :sell_mode_matches_hotel_exclusivity
  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :single_supplement, numericality: { greater_than_or_equal_to: 0 }
  validates :child_price_multiplier, numericality: { greater_than_or_equal_to: 0 }
  validates :base_occupancy, numericality: { only_integer: true, greater_than: 0 }
  validates :extra_pax_charge, numericality: { greater_than_or_equal_to: 0 }

  before_validation :normalize_currency

  after_commit :sync_with_channel_manager, on: [ :create, :update ]
  after_destroy_commit :delete_from_channel_manager, if: :synced_with_channel_manager?

  def self.sell_modes
    %w[per_room per_person]
  end

  def special_tier?
    special_tier_kind.present?
  end

  def standard_rate?
    name.to_s.strip.downcase == "standard rate"
  end

  def deletable?
    !special_tier? && !standard_rate? && !booking_rooms.exists?
  end

  def age_banded?
    sell_mode == "per_person" && rate_plan_age_bands.any?
  end

  def band_for_age(age)
    rate_plan_age_bands.find { |band| age.to_i.between?(band.min_age, band.max_age) }
  end

  def special_tier_kind
    normalized = name.to_s.strip.downcase
    if normalized.in?([ "walk-in rate", "walk in rate", "walk-in", "walk in" ])
      :walk_in
    elsif normalized.in?([ "corporate rate", "corporate" ])
      :corporate
    elsif normalized.in?([ "ota rate", "ota" ])
      :ota
    end
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
  # per_room and per_person. Special tiers (walk-in/corporate/ota) and the
  # system "Standard Rate" plan are exempt because they carry data (e.g.
  # walk_in_price) other parts of the system still read regardless of mode.
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
