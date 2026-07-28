class PaymentTransaction < ApplicationRecord
  belongs_to :booking_quote, optional: true
  belongs_to :booking, optional: true
  belongs_to :corporate_ar_payment_intent, optional: true
  belongs_to :ar_payment, optional: true
  has_one :receipt, dependent: :nullify

  STATUSES = %w[pending captured failed checkout_initiated authorized].freeze

  validates :gateway, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  before_validation :normalize_references

  scope :captured, -> { where(status: "captured") }
  scope :failed, -> { where(status: "failed") }
  scope :with_payment_method, -> { where.not(payment_method: [ nil, "" ]) }

  private

  def normalize_references
    self.external_reference = external_reference.presence
  end
end
