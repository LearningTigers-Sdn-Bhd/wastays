# frozen_string_literal: true

# "Stay at least min_nights, get value off" on a rate plan. from_night 1 means
# every night of the stay is discounted; from_night 2 leaves the first night at
# full price and discounts the rest, and so on.
class RatePlanStayDiscount < ApplicationRecord
  DISCOUNT_TYPES = %w[percent amount].freeze

  belongs_to :rate_plan

  validates :min_nights, numericality: { only_integer: true, greater_than_or_equal_to: 2 }
  validates :min_nights, uniqueness: { scope: :rate_plan_id, message: "already has a discount" }
  validates :discount_type, inclusion: { in: DISCOUNT_TYPES }
  validates :value, numericality: { greater_than: 0 }
  validates :value, numericality: { less_than_or_equal_to: 100, message: "can't be more than 100%" }, if: :percent?
  validates :from_night, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validate :from_night_within_stay

  def percent? = discount_type == "percent"

  def every_night? = from_night.to_i <= 1

  # One night's price after the discount. Night numbers start at 1. An amount
  # is taken off per guest on a per-person plan, per room otherwise, and never
  # takes a night below zero.
  def apply(price, night_number:, guests: 1)
    price = price.to_d
    return price if night_number < from_night.to_i

    discounted = percent? ? price * (1 - (value.to_d / 100)) : price - (value.to_d * guests)
    [ discounted, 0.to_d ].max.round(2)
  end

  private

  def from_night_within_stay
    return if min_nights.blank? || from_night.blank? || from_night <= min_nights

    errors.add(:from_night, "must be within the #{min_nights}-night minimum")
  end
end
