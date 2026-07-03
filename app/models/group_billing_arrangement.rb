# frozen_string_literal: true

class GroupBillingArrangement < ApplicationRecord
  PAYER_TYPES = %w[guest company].freeze
  SETTLEMENT_TYPES = %w[cash_bank city_ledger].freeze
  STATUSES = %w[active inactive].freeze

  belongs_to :group_booking
  belongs_to :hotel
  belongs_to :hotel_corporate_account, optional: true
  has_many :booking_billing_assignments, dependent: :restrict_with_error
  has_many :folio_routing_rules, dependent: :restrict_with_error

  validates :name, :payer_type, :settlement_type, :status, presence: true
  validates :payer_type, inclusion: { in: PAYER_TYPES }
  validates :settlement_type, inclusion: { in: SETTLEMENT_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validate :relationships_belong_to_hotel
  validate :company_payer_has_account
  validate :city_ledger_is_eligible
  validate :validity_dates_are_ordered

  scope :active, -> { where(status: "active") }

  private

  def relationships_belong_to_hotel
    errors.add(:group_booking, "must belong to the same hotel") if group_booking.present? && group_booking.hotel_id != hotel_id
    if hotel_corporate_account.present? && hotel_corporate_account.hotel_id != hotel_id
      errors.add(:hotel_corporate_account, "must belong to the same hotel")
    end
  end

  def company_payer_has_account
    errors.add(:hotel_corporate_account, "must be selected for a company payer") if payer_type == "company" && hotel_corporate_account.blank?
  end

  def city_ledger_is_eligible
    return unless settlement_type == "city_ledger" && hotel_corporate_account.present?
    return if hotel_corporate_account.active? && hotel_corporate_account.direct_bill_enabled?

    errors.add(:settlement_type, "requires an active direct-bill corporate account")
  end

  def validity_dates_are_ordered
    return if valid_from.blank? || valid_until.blank? || valid_until >= valid_from

    errors.add(:valid_until, "must be on or after valid from")
  end
end
