class PayoutBatch < ApplicationRecord
  belongs_to :hotel
  has_many :bookings, dependent: :nullify
  
  has_one_attached :receipt

  STATUSES = %w[pending processing paid].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :period_start, :period_end, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :paid, -> { where(status: "paid") }

  def paid?
    status == "paid"
  end
end
