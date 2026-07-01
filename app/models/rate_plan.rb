class RatePlan < ApplicationRecord
  include HotelScopable

  has_many :room_type_rate_plans, dependent: :destroy
  has_many :room_types, through: :room_type_rate_plans
  has_many :room_rates, dependent: :destroy
  has_one :channel_mapping, as: :mappable, dependent: :destroy

  validates :name, presence: true
  validates :sell_mode, presence: true, inclusion: { in: %w[per_room per_person] }
  validate :pax_pricing_allowed_for_person_mode
  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :single_supplement, numericality: { greater_than_or_equal_to: 0 }
  validates :child_price_multiplier, numericality: { greater_than_or_equal_to: 0 }
  validates :infant_price_multiplier, numericality: { greater_than_or_equal_to: 0 }
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
