# frozen_string_literal: true

class HotelDiscount < ApplicationRecord
  PRICING_TYPES = %w[manual fixed percentage].freeze
  APPLICATION_SCOPES = %w[room_charges all_eligible_charges selected_charges].freeze

  belongs_to :hotel
  belongs_to :transaction_code
  has_many :hotel_discount_transaction_codes, dependent: :destroy
  has_many :applicable_transaction_codes, through: :hotel_discount_transaction_codes, source: :transaction_code

  delegate :name, :name=, :code, :code=, :active, :active=, to: :transaction_code

  validates :transaction_code_id, uniqueness: true
  validates :pricing_type, inclusion: { in: PRICING_TYPES }
  validates :application_scope, inclusion: { in: APPLICATION_SCOPES }
  validates :rate_value, numericality: { greater_than: 0 }, if: :priced?
  validates :rate_value, absence: true, if: :manual?
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :transaction_code_belongs_to_hotel
  validate :transaction_code_is_discount
  validate :transaction_code_code_is_short
  validate :percentage_rate_is_valid
  validate :percentage_amount_cannot_be_overridden
  validate :selected_scope_has_codes

  scope :active, -> { joins(:transaction_code).merge(TransactionCode.active) }
  scope :ordered, -> { order(:position, :id) }

  def manual? = pricing_type == "manual"
  def fixed? = pricing_type == "fixed"
  def percentage? = pricing_type == "percentage"
  def priced? = fixed? || percentage?
  def active? = transaction_code.active?
  def selected_charges? = application_scope == "selected_charges"

  def pricing_label
    return "Enter when applying" if manual?
    return "#{formatted_rate}%" if percentage?

    "#{hotel.default_currency} #{formatted_rate}"
  end

  def application_scope_label
    return "All eligible charges" if application_scope == "all_eligible_charges"

    application_scope.humanize
  end

  def formatted_rate
    ActiveSupport::NumberHelper.number_to_rounded(rate_value.to_d, precision: 2, delimiter: ",", strip_insignificant_zeros: false)
  end

  private

  def transaction_code_belongs_to_hotel
    return if hotel.blank? || transaction_code.blank? || transaction_code.hotel_id == hotel_id

    errors.add(:transaction_code, "must belong to the same hotel")
  end

  def transaction_code_is_discount
    return if transaction_code.blank? || (transaction_code.kind == "adjustment" && transaction_code.category == "discount")

    errors.add(:transaction_code, "must be an adjustment discount code")
  end

  def transaction_code_code_is_short
    errors.add(:code, "must be 10 characters or fewer") if transaction_code&.code.to_s.length > 10
  end

  def percentage_rate_is_valid
    errors.add(:rate_value, "must be 100 or less for percentage pricing") if percentage? && rate_value.present? && rate_value.to_d > 100
  end

  def percentage_amount_cannot_be_overridden
    errors.add(:allow_amount_override, "must be disabled for percentage pricing") if percentage? && allow_amount_override?
  end

  def selected_scope_has_codes
    return unless selected_charges?
    return if applicable_transaction_codes.any?

    errors.add(:applicable_transaction_codes, "must include at least one charge code")
  end
end
