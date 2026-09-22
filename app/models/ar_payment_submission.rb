# frozen_string_literal: true

class ArPaymentSubmission < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :hotel
  belongs_to :hotel_corporate_account
  belongs_to :submitted_by, class_name: "User"
  belongs_to :ar_payment, optional: true, inverse_of: :ar_payment_submission
  # A standard agent has no invoice until checkout, so a remittance sent to meet
  # a booking's payment deadline names the booking instead. See
  # Bookings::PaymentHold.
  belongs_to :booking, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_many :ar_payment_submission_allocations, dependent: :destroy, inverse_of: :ar_payment_submission
  has_many :ar_invoices, through: :ar_payment_submission_allocations

  accepts_nested_attributes_for :ar_payment_submission_allocations

  has_one_attached :slip

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, :reference_number, :received_at, :payment_method, presence: true
  validates :payment_method, inclusion: { in: ArPayment::PAYMENT_METHODS }
  validates :slip, presence: true, on: :create
  validates :rejection_reason, presence: true, if: :rejected?
  validate :hotel_corporate_account_matches_hotel
  # Agents settle specific outstanding invoice(s) via manual bank transfer — one remittance can
  # cover several invoices at once, but it must always target at least one. Only enforced on
  # create so submissions recorded before this requirement can still be approved/rejected.
  # A prepayment sent to meet a booking's payment deadline targets that booking
  # instead: a standard account has no invoice until the folio closes at checkout.
  validate :has_a_target, on: :create
  validate :booking_matches_relationship
  validate :allocations_total_matches_amount

  scope :pending, -> { where(status: "pending") }
  scope :for_booking, ->(booking) { where(booking: booking) }

  def approve!(ar_payment:, reviewed_by:)
    transaction do
      update!(status: "approved", ar_payment: ar_payment, reviewed_by: reviewed_by, reviewed_at: Time.current)
      # The rooms are paid for, so nothing is left to release.
      booking&.update!(payment_due_at: nil)
    end
  end

  def reject!(reason:, reviewed_by:)
    transaction do
      rejected = update(status: "rejected", rejection_reason: reason, reviewed_by: reviewed_by, reviewed_at: Time.current)
      restart_payment_clock if rejected
      rejected
    end
  end

  # Uploading a slip stops the payment clock; a rejection restarts it. The agent
  # gets back the time the hotel spent reviewing, so a slow review cannot cost
  # them the rooms -- but a booking already past its arrival is not pushed out.
  def restart_payment_clock
    return if booking.blank? || booking.payment_due_at.blank?

    review_duration = reviewed_at - created_at
    extended = [ booking.payment_due_at + review_duration, booking.check_in ].compact.min
    booking.update!(payment_due_at: extended)
  end

  private

  def hotel_corporate_account_matches_hotel
    return if hotel.blank? || hotel_corporate_account.blank?
    return if hotel_corporate_account.hotel_id == hotel_id

    errors.add(:hotel_corporate_account, "must belong to the submission hotel")
  end

  def active_allocations
    ar_payment_submission_allocations.reject(&:marked_for_destruction?)
  end

  def has_a_target
    return if active_allocations.any? || booking_id.present?

    errors.add(:base, "must target at least one outstanding invoice or a booking")
  end

  def booking_matches_relationship
    return if booking.blank?
    return if booking.hotel_corporate_account_id == hotel_corporate_account_id

    errors.add(:booking, "must belong to the same corporate account")
  end

  def allocations_total_matches_amount
    return if amount.blank? || active_allocations.empty?

    total = active_allocations.sum { |allocation| allocation.amount.to_d }
    errors.add(:amount, "must equal the sum of the allocated invoice amounts") if total != amount.to_d
  end
end
