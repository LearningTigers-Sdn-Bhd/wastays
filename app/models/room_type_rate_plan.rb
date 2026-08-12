class RoomTypeRatePlan < ApplicationRecord
  belongs_to :room_type
  belongs_to :rate_plan
  has_one :channel_mapping, as: :mappable, dependent: :destroy
  has_many :occupancy_prices,
    class_name: "RoomTypeRatePlanOccupancyPrice",
    dependent: :destroy,
    inverse_of: :room_type_rate_plan

  attr_accessor :included

  validates :pricing_mode, presence: true, inclusion: { in: %w[fixed multiplier offset] }
  validates :rate_plan_id, uniqueness: { scope: :room_type_id }
  validates :pricing_value, presence: true, numericality: true, unless: -> { pricing_mode == "fixed" }
  validates :pricing_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true, if: -> { pricing_mode == "fixed" }
  validates :base_occupancy, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :extra_pax_charge, :single_supplement,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  after_commit :trigger_ari_sync, on: [ :create, :update ]

  # Occupancy rules narrow from the plan to this pairing. Null means the pair
  # has nothing of its own to say, so the plan answers — which is what every
  # assignment written before these columns existed relies on.
  OCCUPANCY_RULES = %i[base_occupancy extra_pax_charge single_supplement].freeze

  OCCUPANCY_RULES.each do |rule|
    define_method(:"effective_#{rule}") { self[rule].presence || rate_plan&.public_send(rule) }
  end

  def derives_price?
    pricing_mode.in?(%w[multiplier offset])
  end

  def derive_price(anchor_price)
    return nil if anchor_price.nil? || pricing_value.nil?

    result = case pricing_mode
    when "multiplier" then anchor_price * (1 + pricing_value / 100.to_d)
    when "offset" then anchor_price + pricing_value
    else
      anchor_price
    end

    [ result, 0.to_d ].max
  end

  def occupancy_price_for(adults)
    occupancy_prices.find { |item| item.adults == adults.to_i }&.price
  end

  private

  def trigger_ari_sync
    return if Thread.current[:skip_ari_sync]
    return if room_type.hotel.preferred_channel_manager.blank?

    ChannelManagers::SyncRatePlanAri.call(rate_plan: rate_plan, room_type_ids: [ room_type_id ])
  end
end
