class RoomRate < ApplicationRecord
  OCCUPANCY_KEY_FORMAT = /\A[1-9]\d*\z/

  belongs_to :room_type
  belongs_to :rate_plan, optional: true

  validates :date, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :date, uniqueness: { scope: [ :room_type_id, :rate_plan_id, :currency ] }
  validates :min_stay, numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validates :max_stay, numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validates :base_occupancy, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :extra_pax_charge, :single_supplement,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :occupancy_prices_are_valid

  before_validation :normalize_currency
  after_commit :trigger_ari_sync, on: [ :create, :update ]

  private

  def normalize_currency
    self.currency = CurrencyCatalog.normalize(currency)
  end

  # Runs alongside the belongs_to :room_type presence check rather than after
  # it, so it cannot assume a room_type is there, and it is fed straight from
  # jsonb / form params, so it cannot assume the values are numeric either.
  # Both used to raise NoMethodError out of a plain `valid?`.
  def occupancy_prices_are_valid
    return if occupancy_prices.blank?

    unless occupancy_prices.is_a?(Hash)
      errors.add(:occupancy_prices, "must map an adult count to a price")
      return
    end

    # Collected rather than added per entry: one malformed matrix should read as
    # one problem, not the same sentence repeated once per occupancy.
    bad_occupancy = occupancy_prices.keys.any? { |adults| !valid_occupancy_key?(adults) }
    bad_price = occupancy_prices.values.any? { |amount| !valid_occupancy_amount?(amount) }

    errors.add(:occupancy_prices, "contains an adult occupancy outside the room category capacity") if bad_occupancy
    errors.add(:occupancy_prices, "must contain non-negative prices") if bad_price
  end

  def valid_occupancy_key?(adults)
    return false unless adults.to_s.match?(OCCUPANCY_KEY_FORMAT)
    # A missing room_type is the belongs_to's error to report; don't mask it
    # with a capacity failure we have no capacity to measure against.
    return true if room_type.blank?

    adults.to_i <= room_type.max_adults.to_i
  end

  def valid_occupancy_amount?(amount)
    numeric = Kernel::Float(amount, exception: false)
    numeric.present? && !numeric.negative?
  end

  PRICE_ATTRIBUTES = %w[price occupancy_prices base_occupancy extra_pax_charge single_supplement].freeze
  RESTRICTION_ATTRIBUTES = %w[min_stay max_stay closed_to_arrival closed_to_departure stop_sell].freeze

  # Buffers a price change and a restriction change separately, so each goes
  # out with the fields it touched. A new rate carries both.
  def trigger_ari_sync
    return if Thread.current[:skip_ari_sync]
    return unless room_type.hotel.channel_manager_enabled?

    changed = previously_new_record? ? PRICE_ATTRIBUTES + RESTRICTION_ATTRIBUTES : saved_changes.keys
    types = []
    types << :rates if changed.intersect?(PRICE_ATTRIBUTES)
    types << :restrictions if changed.intersect?(RESTRICTION_ATTRIBUTES)

    types.each do |type|
      ChannelManagers::BufferAriSyncJob.perform_later(room_type.hotel_id, date, type: type, rate_plan_id: rate_plan_id)
    end
  end
end
