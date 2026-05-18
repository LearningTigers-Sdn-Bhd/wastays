class HotelPricingRule < ApplicationRecord
  belongs_to :hotel

  RULE_TYPES = %w[general weekends school_holiday public_holiday walk_in corporate_rate].freeze

  validates :rule_type, presence: true, inclusion: { in: RULE_TYPES }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :valid_date_range
  validate :public_holiday_requires_name
  validate :weekends_requires_weekdays

  scope :public_holidays, -> { where(rule_type: "public_holiday") }

  private

  def valid_date_range
    return if start_date.blank? && end_date.blank?
    return if start_date.present? && end_date.present? && end_date >= start_date

    errors.add(:end_date, "cannot be earlier than start date")
  end

  def public_holiday_requires_name
    return unless rule_type == "public_holiday"
    return if name.present?

    errors.add(:name, "is required for public holiday rules")
  end

  def weekends_requires_weekdays
    return unless rule_type == "weekends"
    return if weekdays.present?

    errors.add(:weekdays, "is required for weekends rules")
  end
end
