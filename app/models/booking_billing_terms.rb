# frozen_string_literal: true

class BookingBillingTerms < ApplicationRecord
  SETTLEMENT_TYPES = %w[cash_bank city_ledger].freeze

  belongs_to :booking_billing_party
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true

  enum :settlement_type, SETTLEMENT_TYPES.index_by(&:itself), validate: true

  validates :booking_billing_party_id, uniqueness: true
  validates :settlement_type, presence: true
  validates :purchase_order_reference, presence: true, if: -> { settlement_type == "city_ledger" }
  validate :city_ledger_requires_eligible_company

  private

  def city_ledger_requires_eligible_company
    return unless settlement_type == "city_ledger"

    party = booking_billing_party
    account = party&.hotel_corporate_account
    unless party&.company? && account&.active? && account&.direct_bill_enabled?
      errors.add(:settlement_type, "requires an active Direct Bill Company & Government Account")
    end
  end
end
