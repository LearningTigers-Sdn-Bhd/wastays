class RatePlanAgeBand < ApplicationRecord
  belongs_to :rate_plan

  default_scope { order(:position, :min_age) }

  validates :min_age, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_age, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :price_multiplier, numericality: { greater_than_or_equal_to: 0 }
  validate :max_age_after_min_age
  validate :no_overlap_with_siblings

  private

  def max_age_after_min_age
    return if min_age.nil? || max_age.nil?

    errors.add(:max_age, "must be greater than or equal to min age") if max_age < min_age
  end

  def no_overlap_with_siblings
    return if min_age.nil? || max_age.nil? || rate_plan.nil?

    siblings = rate_plan.rate_plan_age_bands.where.not(id: id)
    overlapping = siblings.any? { |band| min_age <= band.max_age && max_age >= band.min_age }
    errors.add(:base, "age band overlaps with another band on this rate plan") if overlapping
  end
end
