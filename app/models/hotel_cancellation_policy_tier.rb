# frozen_string_literal: true

# One band of a cancellation policy: "cancel at least N days before arrival and
# the hotel keeps this much".
#
# A tier stores what is *retained* — never the refund. The refund is derived
# (`amount_paid - fee`), because storing both invites a policy that keeps 30% and
# refunds 50% with nobody able to say where the rest went.
class HotelCancellationPolicyTier < ApplicationRecord
  PRICING_TYPES = %w[fixed percentage nights].freeze
  PERCENTAGE_BASES = %w[first_night total_stay remaining_nights].freeze

  belongs_to :hotel_reservation_policy, inverse_of: :cancellation_tiers

  validates :days_before_arrival, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :hotel_reservation_policy_id }
  validates :pricing_type, inclusion: { in: PRICING_TYPES }
  validates :percentage_basis, inclusion: { in: PERCENTAGE_BASES }, allow_nil: true
  # Zero is meaningful here in a way it is not on the parent policy: a 0% tier is
  # how a hotel expresses "free cancellation up to this point".
  validates :rate_value, numericality: { greater_than_or_equal_to: 0 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :percentage_has_basis
  validate :percentage_rate_is_valid
  validate :nights_are_whole
  validate :belongs_to_a_cancellation_policy

  scope :ordered, -> { order(:days_before_arrival) }

  def percentage? = pricing_type == "percentage"
  def fixed? = pricing_type == "fixed"
  def nights? = pricing_type == "nights"

  # A tier that keeps nothing — the guest is made whole.
  def free_cancellation? = rate_value.to_d.zero?

  def whole_nights = rate_value.to_i

  def label
    prefix = days_before_arrival.zero? ? "Less than 1 day before arrival" : "#{days_before_arrival}+ days before arrival"
    "#{prefix}: #{retention_label}"
  end

  def retention_label
    return "No charge" if free_cancellation?
    return "keep #{formatted_rate}% of #{(percentage_basis || 'total_stay').humanize.downcase}" if percentage?
    return "keep #{whole_nights} #{'night'.pluralize(whole_nights)}" if nights?

    "keep #{hotel_reservation_policy.hotel.default_currency} #{formatted_rate}"
  end

  def formatted_rate
    ActiveSupport::NumberHelper.number_to_rounded(rate_value.to_d, precision: 2, delimiter: ",", strip_insignificant_zeros: false)
  end

  private

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

  def belongs_to_a_cancellation_policy
    return if hotel_reservation_policy.blank? || hotel_reservation_policy.cancellation?

    errors.add(:hotel_reservation_policy, "must be a cancellation policy")
  end
end
