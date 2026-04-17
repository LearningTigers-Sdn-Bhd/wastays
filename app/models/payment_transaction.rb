class PaymentTransaction < ApplicationRecord
  belongs_to :booking_quote, optional: true
  belongs_to :booking, optional: true

  STATUSES = %w[pending captured failed checkout_initiated authorized].freeze

  validates :gateway, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :captured, -> { where(status: "captured") }
  scope :failed, -> { where(status: "failed") }
  scope :with_payment_method, -> { where.not(payment_method: [ nil, "" ]) }
end
