# frozen_string_literal: true

class HotelExtraCharge < ApplicationRecord
  NIGHTLY_CHARGING_UNITS = %w[per_night per_room_night per_person_night].freeze
  PRICING_TYPES = %w[manual fixed percentage].freeze
  CHARGING_UNITS = %w[per_item per_stay per_night per_room per_room_night per_person per_person_night].freeze
  PERCENTAGE_BASES = %w[room_charges non_tax_charges].freeze

  belongs_to :hotel
  belongs_to :transaction_code

  delegate :name, :name=, :code, :code=, :category, :category=, :active, :active=,
    :tax_rule_keys, to: :transaction_code

  validates :transaction_code_id, uniqueness: true
  validates :pricing_type, inclusion: { in: PRICING_TYPES }
  validates :charging_unit, inclusion: { in: CHARGING_UNITS }
  validates :rate_value, numericality: { greater_than: 0 }, if: :priced?
  validates :rate_value, absence: true, if: :manual?
  validates :percentage_basis, inclusion: { in: PERCENTAGE_BASES }, if: :percentage?
  validates :percentage_basis, absence: true, unless: :percentage?
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :transaction_code_belongs_to_hotel
  validate :transaction_code_is_charge
  validate :transaction_code_is_not_tax_managed
  validate :transaction_code_code_is_short
  validate :percentage_rate_is_valid
  validate :percentage_amount_cannot_be_overridden

  scope :active, -> { joins(:transaction_code).merge(TransactionCode.active) }
  scope :ordered, -> { order(:position, :id) }

  def manual? = pricing_type == "manual"
  def fixed? = pricing_type == "fixed"
  def percentage? = pricing_type == "percentage"
  def priced? = fixed? || percentage?
  def active? = transaction_code.active?
  def nightly? = charging_unit.in?(NIGHTLY_CHARGING_UNITS)

  def pricing_label
    return "Enter when charging" if manual?
    return "#{formatted_rate}% of #{percentage_basis.to_s.humanize.downcase}" if percentage?

    "#{hotel.default_currency} #{formatted_rate} · #{charging_unit.to_s.humanize.downcase}"
  end

  def formatted_rate
    ActiveSupport::NumberHelper.number_to_rounded(rate_value.to_d, precision: 2, delimiter: ",", strip_insignificant_zeros: false)
  end

  private

  def transaction_code_belongs_to_hotel
    return if hotel.blank? || transaction_code.blank? || transaction_code.hotel_id == hotel_id

    errors.add(:transaction_code, "must belong to the same hotel")
  end

  def transaction_code_is_charge
    return if transaction_code.blank? || transaction_code.kind == "charge"

    errors.add(:transaction_code, "must be a charge code")
  end

  def transaction_code_is_not_tax_managed
    return if transaction_code.blank? || hotel.blank?
    return unless hotel.hotel_taxes.where(transaction_code_id: transaction_code.id).exists?

    errors.add(:transaction_code, "is managed by Taxes & Fees")
  end

  def transaction_code_code_is_short
    return if transaction_code.blank? || transaction_code.code.to_s.length <= 10

    errors.add(:code, "must be 10 characters or fewer")
  end

  def percentage_rate_is_valid
    return unless percentage? && rate_value.present? && rate_value.to_d > 100

    errors.add(:rate_value, "must be 100 or less for percentage pricing")
  end

  def percentage_amount_cannot_be_overridden
    return unless percentage? && allow_amount_override?

    errors.add(:allow_amount_override, "must be disabled for percentage pricing")
  end
end
