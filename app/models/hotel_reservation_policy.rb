# frozen_string_literal: true

# What a hotel charges when a stay does not run as booked: a late checkout, an
# early departure, a no-show, a cancellation.
#
# All four bill a room night, so none of them carries tax rules of its own —
# TransactionCodes::Resolver#tax_rule_source_for sends them to ROOM. What differs
# between them is only the policy: whether to charge, and how much.
class HotelReservationPolicy < ApplicationRecord
  POLICY_TYPES = %w[late_checkout early_departure no_show cancellation].freeze
  PRICING_TYPES = %w[manual fixed percentage nights].freeze
  PERCENTAGE_BASES = %w[first_night total_stay remaining_nights].freeze
  REFUND_METHODS = %w[original_payment_method bank_transfer credit_note].freeze

  belongs_to :hotel
  belongs_to :transaction_code
  has_many :cancellation_tiers, -> { order(:days_before_arrival) },
    class_name: "HotelCancellationPolicyTier", dependent: :destroy, inverse_of: :hotel_reservation_policy

  accepts_nested_attributes_for :cancellation_tiers, allow_destroy: true

  delegate :name, :code, to: :transaction_code

  validates :policy_type, inclusion: { in: POLICY_TYPES }, uniqueness: { scope: :hotel_id }
  validates :pricing_type, inclusion: { in: PRICING_TYPES }
  validates :percentage_basis, inclusion: { in: PERCENTAGE_BASES }, allow_nil: true
  validates :refund_method, inclusion: { in: REFUND_METHODS }, allow_nil: true
  validates :rate_value, numericality: { greater_than: 0 }, if: :priced?
  validates :rate_value, absence: true, if: :manual?
  validates :refund_processing_days, numericality: { only_integer: true, in: 0..365 }, allow_nil: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :transaction_code_belongs_to_hotel
  validate :percentage_has_basis
  validate :percentage_rate_is_valid
  validate :nights_are_whole
  validate :no_show_charges_whole_nights
  validate :refund_terms_are_cancellation_only

  scope :ordered, -> { order(:position, :id) }
  scope :charging, -> { where(active: true) }

  def manual? = pricing_type == "manual"
  def fixed? = pricing_type == "fixed"
  def percentage? = pricing_type == "percentage"
  def nights? = pricing_type == "nights"
  def priced? = fixed? || percentage? || nights?
  def cancellation? = policy_type == "cancellation"
  def no_show? = policy_type == "no_show"

  # Whether the booking action sheet may offer a "custom" amount alongside
  # "follow policy". A manual policy is nothing but the custom path.
  def overridable? = manual? || allow_amount_override?

  def policy_type_label = policy_type.humanize

  def pricing_label
    return "Not charged" unless active?
    return "Staff enters amount" if manual?
    return "#{formatted_rate}% of #{(percentage_basis || 'total_stay').humanize.downcase}" if percentage?
    return "#{whole_nights} #{'night'.pluralize(whole_nights)} at room rate" if nights?

    "#{hotel.default_currency} #{formatted_rate}"
  end

  def whole_nights = rate_value.to_i

  # rate_value is a decimal column, so a night count comes back as 1.0. A number
  # input stepping in whole numbers rejects that, so nights render without the
  # fractional part; money and percentages keep theirs.
  def rate_value_for_input
    return if rate_value.blank?

    nights? ? whole_nights : rate_value
  end

  def formatted_rate
    ActiveSupport::NumberHelper.number_to_rounded(rate_value.to_d, precision: 2, delimiter: ",", strip_insignificant_zeros: false)
  end

  private

  def transaction_code_belongs_to_hotel
    return if hotel.blank? || transaction_code.blank? || transaction_code.hotel_id == hotel_id

    errors.add(:transaction_code, "must belong to the same hotel")
  end

  def percentage_has_basis
    errors.add(:percentage_basis, "is required for percentage pricing") if percentage? && percentage_basis.blank?
  end

  def percentage_rate_is_valid
    errors.add(:rate_value, "must be 100 or less for percentage pricing") if percentage? && rate_value.present? && rate_value.to_d > 100
  end

  def nights_are_whole
    return unless nights? && rate_value.present?

    errors.add(:rate_value, "must be a whole number of nights") if rate_value.to_d != rate_value.to_d.truncate
  end

  # A no-show fee is posted alongside the booking's per-night tax snapshot, which
  # carries one tax line per night. Charging a percentage or a flat sum would leave
  # the fee and its own tax describing different amounts.
  def no_show_charges_whole_nights
    errors.add(:pricing_type, "must be whole nights for a no-show policy") if no_show? && !nights?
  end

  def refund_terms_are_cancellation_only
    return if cancellation?
    return if refund_processing_days.blank? && refund_method.blank?

    errors.add(:base, "Refund terms only apply to a cancellation policy")
  end
end
