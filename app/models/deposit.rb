# frozen_string_literal: true

class Deposit < ApplicationRecord
  KINDS = %w[security prepayment].freeze
  STATUSES = %w[pending held available settled released refunded cancelled failed].freeze

  belongs_to :hotel
  belongs_to :booking, optional: true
  belongs_to :group_booking, optional: true
  belongs_to :hotel_corporate_account, optional: true
  belongs_to :transaction_code
  belongs_to :received_by, class_name: "User", optional: true
  has_many :deposit_movements, -> { chronological }, dependent: :restrict_with_error,
    inverse_of: :deposit
  has_one :receipt, dependent: :restrict_with_error

  after_create :issue_payment_receipt
  after_update :issue_payment_receipt, if: :became_receiptable?

  enum :kind, KINDS.index_by(&:itself), prefix: true, validate: true
  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :amount, numericality: { greater_than: 0 }
  validates :currency, :payment_method, :received_at, presence: true
  validates :external_reference, uniqueness: { scope: %i[hotel_id booking_id group_booking_id], allow_blank: true }
  validate :exactly_one_owner
  validate :relationships_belong_to_hotel
  validate :transaction_code_matches_kind

  def owner
    booking || group_booking
  end

  def applied_amount
    movement_total("apply") - movement_total("reverse")
  end

  def released_amount
    movement_total("release")
  end

  def refunded_amount
    movement_total("refund")
  end

  def returned_amount
    released_amount + refunded_amount
  end

  def available_amount
    amount - applied_amount - returned_amount
  end

  def eligible_folio?(folio)
    return false unless folio&.hotel_id == hotel_id && folio.currency == currency
    return false if hotel_corporate_account_id.present? && folio.hotel_corporate_account_id != hotel_corporate_account_id
    return folio.booking_id == booking_id if booking_id.present?

    folio.booking.group_booking_id == group_booking_id
  end

  def refresh_status!
    next_status = if available_amount.positive?
      kind_security? ? "held" : "available"
    elsif applied_amount.positive?
      "settled"
    elsif kind_security?
      "released"
    else
      "refunded"
    end
    update!(status: next_status)
  end

  private

  def issue_payment_receipt
    Receipts::Issue.call!(source: self)
  end

  def became_receiptable?
    saved_change_to_status? && status.in?(%w[held available settled]) && receipt.blank?
  end

  def movement_total(type)
    if deposit_movements.loaded?
      deposit_movements.select { |movement| movement.movement_type == type }.sum { |movement| movement.amount.to_d }
    else
      deposit_movements.where(movement_type: type).sum(:amount)
    end
  end

  def exactly_one_owner
    return if booking.present? ^ group_booking.present?

    errors.add(:base, "Deposit must belong to exactly one booking or group booking")
  end

  def relationships_belong_to_hotel
    errors.add(:booking, "must belong to the same hotel") if booking.present? && booking.hotel_id != hotel_id
    errors.add(:group_booking, "must belong to the same hotel") if group_booking.present? && group_booking.hotel_id != hotel_id
    if hotel_corporate_account.present? && hotel_corporate_account.hotel_id != hotel_id
      errors.add(:hotel_corporate_account, "must belong to the same hotel")
    end
    errors.add(:transaction_code, "must belong to the same hotel") if transaction_code.present? && transaction_code.hotel_id != hotel_id
  end

  def transaction_code_matches_kind
    return if transaction_code.blank?

    expected = kind_security? ? "security_deposit" : "booking_payment"
    errors.add(:transaction_code, "must be a #{expected.humanize.downcase} code") unless transaction_code.category == expected
  end
end
