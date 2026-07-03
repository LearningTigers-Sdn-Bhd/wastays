# frozen_string_literal: true

class HotelCorporateAccount < ApplicationRecord
  belongs_to :hotel
  belongs_to :corporate_account, class_name: "Account"
  has_many :ar_invoices, dependent: :restrict_with_error
  has_many :ar_payments, dependent: :restrict_with_error
  has_many :group_billing_arrangements, dependent: :restrict_with_error
  has_many :group_deposits, dependent: :restrict_with_error
  has_many :booking_billing_parties, dependent: :restrict_with_error

  enum :relationship_type, { standard: "standard", direct_bill: "direct_bill" }, prefix: true, validate: true
  enum :status, { active: "active", suspended: "suspended" }, validate: true

  validates :corporate_account_id, uniqueness: { scope: :hotel_id }
  validates :credit_currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :payment_terms_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :corporate_account_kind

  scope :active, -> { where(status: "active") }
  scope :suspended, -> { where(status: "suspended") }

  def suspend!
    update!(status: "suspended", suspended_at: Time.current)
  end

  def reactivate!
    update!(status: "active", suspended_at: nil)
  end

  private

  def corporate_account_kind
    return if corporate_account.blank? || corporate_account.corporate?

    errors.add(:corporate_account, "must be a corporate account")
  end
end
