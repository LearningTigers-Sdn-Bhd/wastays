# frozen_string_literal: true

# What one room category charges for a child in one age band, on one rate plan.
#
# The band owns the age range and the label; this owns only the money. A band
# with no row here falls back to its own price_value, which is what every plan
# priced by before the pairing could hold a figure of its own.
class RoomTypeRatePlanAgeBandPrice < ApplicationRecord
  belongs_to :room_type_rate_plan
  belongs_to :rate_plan_age_band

  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :rate_plan_age_band_id, uniqueness: { scope: :room_type_rate_plan_id }
  validate :band_belongs_to_the_same_rate_plan

  private

  # A price for a band on some other plan would never be read, and would quietly
  # look like configuration that had been done.
  def band_belongs_to_the_same_rate_plan
    return if rate_plan_age_band.blank? || room_type_rate_plan.blank?
    return if rate_plan_age_band.rate_plan_id == room_type_rate_plan.rate_plan_id

    errors.add(:rate_plan_age_band, "belongs to a different rate plan")
  end
end
