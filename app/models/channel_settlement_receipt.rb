# frozen_string_literal: true

class ChannelSettlementReceipt < ApplicationRecord
  SETTLEMENT_METHODS = ChannelSettlement::SETTLEMENT_METHODS

  belongs_to :hotel
  belongs_to :booking_source
  belongs_to :hotel_payment_method
  belongs_to :recorded_by, class_name: "User"
  has_many :channel_settlement_receipt_allocations, dependent: :restrict_with_error
  has_many :channel_settlement_allocations, through: :channel_settlement_receipt_allocations
  has_many :channel_settlements, through: :channel_settlement_allocations

  enum :settlement_method, SETTLEMENT_METHODS.index_by(&:itself), prefix: true, validate: true

  validates :amount, :currency, :received_at, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :currency, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :external_reference, uniqueness: { scope: :hotel_id }, allow_blank: true
  validate :booking_source_is_ota
  validate :payment_method_belongs_to_hotel

  private

  def booking_source_is_ota
    return if booking_source.blank? || booking_source.kind == "ota"

    errors.add(:booking_source, "must be an OTA booking source")
  end

  def payment_method_belongs_to_hotel
    return if hotel_payment_method.blank? || hotel.blank?
    return if hotel_payment_method.hotel_id == hotel_id

    errors.add(:hotel_payment_method, "must belong to the receipt hotel")
  end
end
