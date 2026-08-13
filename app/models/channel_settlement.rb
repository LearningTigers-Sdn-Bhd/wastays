# frozen_string_literal: true

class ChannelSettlement < ApplicationRecord
  COLLECTION_RESPONSIBILITIES = %w[property ota unknown].freeze
  SETTLEMENT_METHODS = %w[guest_card virtual_card bank_transfer unknown].freeze
  STATUSES = %w[
    property_collection_required
    awaiting_ota_settlement
    virtual_card_not_ready
    ready_to_charge
    partially_received
    received
    underpaid
    overpaid
    failed
    cancelled
    needs_attention
    unknown
  ].freeze

  belongs_to :hotel
  belongs_to :booking_source
  has_many :channel_settlement_allocations, dependent: :restrict_with_error
  has_many :bookings, through: :channel_settlement_allocations
  has_many :booking_folios, through: :channel_settlement_allocations
  has_many :channel_settlement_receipt_allocations, through: :channel_settlement_allocations
  has_many :channel_settlement_receipts, through: :channel_settlement_receipt_allocations

  enum :collection_by, COLLECTION_RESPONSIBILITIES.index_by(&:itself), prefix: true, validate: true
  enum :settlement_method, SETTLEMENT_METHODS.index_by(&:itself), prefix: true, validate: true
  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :provider, :channel_manager_reference, :currency, presence: true
  validates :currency, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :gross_amount, :expected_net_amount, presence: true,
    numericality: { greater_than_or_equal_to: 0 }
  validates :commission_amount, presence: true,
    numericality: { greater_than_or_equal_to: 0 }
  validates :channel_manager_reference, uniqueness: { scope: [ :hotel_id, :provider ] }
  validates :virtual_card_currency, inclusion: { in: ->(_) { CurrencyCatalog.codes } }, allow_blank: true
  validates :virtual_card_available_balance, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :booking_source_is_ota
  validate :commission_does_not_exceed_gross_amount
  validate :expected_net_matches_components

  private

  def booking_source_is_ota
    return if booking_source.blank? || booking_source.kind == "ota"

    errors.add(:booking_source, "must be an OTA booking source")
  end

  def commission_does_not_exceed_gross_amount
    return if gross_amount.blank? || commission_amount.blank?
    return unless commission_amount.to_d > gross_amount.to_d

    errors.add(:commission_amount, "must not exceed gross amount")
  end

  def expected_net_matches_components
    return if gross_amount.blank? || commission_amount.blank? || expected_net_amount.blank?
    return if expected_net_amount.to_d == (gross_amount.to_d - commission_amount.to_d)

    errors.add(:expected_net_amount, "must equal gross amount minus commission amount")
  end
end
