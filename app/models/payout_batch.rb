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

  scope :period_between, ->(start_date, end_date) {
    scope = all
    scope = scope.where("period_end >= ?", start_date.beginning_of_day) if start_date.present?
    scope = scope.where("period_end <= ?", end_date.end_of_day) if end_date.present?
    scope
  }

  scope :search, ->(query) {
    return all if query.blank?
    joins(:hotel).where(
      "hotels.name ILIKE :q OR payout_reference ILIKE :q",
      q: "%#{query}%"
    )
  }

  def paid?
    status == "paid"
  end
end
