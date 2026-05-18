class RoomRate < ApplicationRecord
  belongs_to :room_type
  belongs_to :rate_plan, optional: true

  validates :date, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :date, uniqueness: { scope: [ :room_type_id, :rate_plan_id, :currency ] }
  validates :min_stay, numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validates :max_stay, numericality: { only_integer: true, greater_than: 0, allow_nil: true }

  before_validation :normalize_currency
  after_commit :trigger_ari_sync, on: [ :create, :update ]

  private

  def normalize_currency
    self.currency = CurrencyCatalog.normalize(currency)
  end

  def trigger_ari_sync
    return if Thread.current[:skip_ari_sync]
    return if room_type.hotel.preferred_channel_manager.blank?

    ChannelManagers::BufferAriSyncJob.perform_later(
      room_type.hotel_id,
      date,
      type: :restrictions,
      rate_plan_id: rate_plan_id
    )
  end
end
