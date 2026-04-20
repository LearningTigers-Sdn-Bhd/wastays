class RefundPolicy < ApplicationRecord
  validates :min_days_before_checkin, presence: true,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :refund_percentage, presence: true,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
end
