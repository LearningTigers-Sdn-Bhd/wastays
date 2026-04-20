class RefundRequest < ApplicationRecord
  belongs_to :booking

  STATUSES = %w[pending approved rejected completed].freeze
  ACCOUNT_TYPES = %w[savings current].freeze

  validates :bank_name, :account_holder_name, :account_number, :account_type, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :account_type, inclusion: { in: ACCOUNT_TYPES }
  validates :refund_amount, presence: true, numericality: { greater_than: 0 }
  validates :booking_id, uniqueness: true

  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
  def completed? = status == "completed"
end
