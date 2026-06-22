class PaymentTransaction < ApplicationRecord
  belongs_to :booking_quote, optional: true
  belongs_to :booking, optional: true

  STATUSES = %w[pending captured failed checkout_initiated authorized].freeze

  validates :gateway, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  before_validation :normalize_references

  scope :captured, -> { where(status: "captured") }
  scope :failed, -> { where(status: "failed") }
  scope :with_payment_method, -> { where.not(payment_method: [ nil, "" ]) }

  def direct_hotel_payment?
    gateway == "manual" || event_source == "manual_booking"
  end

  def wastays_collected_payment?
    !direct_hotel_payment? && booking_quote_id.present?
  end

  private

  def normalize_references
    self.external_reference = external_reference.presence
  end
end
