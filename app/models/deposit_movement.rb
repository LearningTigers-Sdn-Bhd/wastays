# frozen_string_literal: true

class DepositMovement < ApplicationRecord
  MOVEMENT_TYPES = %w[hold receive apply reverse release refund].freeze

  belongs_to :deposit
  belongs_to :booking_folio, optional: true
  belongs_to :folio_transaction, optional: true
  belongs_to :performed_by, class_name: "User", optional: true
  belongs_to :reversal_of, class_name: "DepositMovement", optional: true
  has_one :reversal, class_name: "DepositMovement", foreign_key: :reversal_of_id,
    dependent: :restrict_with_error, inverse_of: :reversal_of

  enum :movement_type, MOVEMENT_TYPES.index_by(&:itself), prefix: true, validate: true

  validates :amount, numericality: { greater_than: 0 }
  validates :occurred_at, presence: true
  validates :operation_key, uniqueness: true, allow_blank: true
  validate :target_shape
  validate :target_is_eligible
  validate :reversal_shape
  before_update :prevent_mutation
  before_destroy :prevent_mutation

  scope :chronological, -> { order(:occurred_at, :id) }

  def immutable?
    persisted?
  end

  private

  def target_shape
    target_required = movement_type.in?(%w[apply reverse])
    if target_required && (booking_folio.blank? || folio_transaction.blank?)
      errors.add(:base, "Application movements require a folio and folio transaction")
    elsif !target_required && (booking_folio.present? || folio_transaction.present?)
      errors.add(:base, "Only application movements may target a folio")
    end
  end

  def target_is_eligible
    return if booking_folio.blank? || deposit.blank?
    return if deposit.eligible_folio?(booking_folio)

    errors.add(:booking_folio, "must belong to the deposit owner")
  end

  def reversal_shape
    if movement_type == "reverse"
      errors.add(:reversal_of, "must reference an application") unless reversal_of&.movement_type == "apply"
    elsif reversal_of.present?
      errors.add(:reversal_of, "is only valid for reversal movements")
    end
  end

  def prevent_mutation
    errors.add(:base, "Deposit movements are immutable")
    throw(:abort)
  end
end
