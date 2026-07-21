class RoomTypeRatePlan < ApplicationRecord
  belongs_to :room_type
  belongs_to :rate_plan
  has_one :channel_mapping, as: :mappable, dependent: :destroy

  attr_accessor :included

  validates :pricing_mode, presence: true, inclusion: { in: %w[fixed multiplier offset] }
  validates :pricing_value, presence: true, numericality: true, unless: -> { pricing_mode == "fixed" }

  after_commit :trigger_ari_sync, on: [ :create, :update ]

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

  private

  def trigger_ari_sync
    return if Thread.current[:skip_ari_sync]
    return if room_type.hotel.preferred_channel_manager.blank?

    # 1. First ensure the Rate Plan structure exists in the Channel Manager
    ChannelManagers::SyncStructureJob.perform_later(self.class.name, id, "sync")

    # 2. Then trigger a sync for a large window to cover future derived prices
    ChannelManagers::SyncJob.perform_later(
      room_type.hotel_id,
      Date.current,
      Date.current + 499.days,
      sync_availability: false,
      sync_rates: true,
      sync_restrictions: true,
      room_type_ids: [ room_type_id ],
      rate_plan_ids: [ rate_plan_id ]
    )
  end
end
