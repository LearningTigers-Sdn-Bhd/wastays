# frozen_string_literal: true

class HotelCorporateAccount < ApplicationRecord
  belongs_to :hotel
  belongs_to :corporate_account, class_name: "Account"
  has_many :ar_invoices, dependent: :restrict_with_error
  has_many :receivables, class_name: "Receivable", dependent: :restrict_with_error
  has_many :ar_payments, dependent: :restrict_with_error
  has_many :ar_payment_submissions, dependent: :restrict_with_error
  has_many :deposits, dependent: :restrict_with_error
  has_many :booking_billing_parties, dependent: :restrict_with_error
  has_many :bookings, dependent: :nullify
  has_many :booking_quotes, dependent: :nullify

  ACCOUNT_TYPES = %w[company government travel_agent airline salesperson].freeze
  UNAVAILABLE_ACCOUNT_TYPES = [].freeze

  enum :relationship_type, { standard: "standard", direct_bill: "direct_bill" }, prefix: true, validate: true
  enum :status, { active: "active", suspended: "suspended" }, validate: true
  enum :account_type, ACCOUNT_TYPES.index_by(&:itself), validate: true

  validates :corporate_account_id, uniqueness: { scope: :hotel_id }
  validates :credit_currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :payment_terms_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :agent_code, uniqueness: { scope: :hotel_id }, allow_nil: true
  validate :corporate_account_kind

  before_validation :generate_agent_code, on: :create
  before_validation :sync_direct_bill_enabled

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

  def sync_direct_bill_enabled
    self.direct_bill_enabled = relationship_type_direct_bill?
  end

  def generate_agent_code
    return if agent_code.present?

    loop do
      self.agent_code = SecureRandom.alphanumeric(6).upcase
      break unless HotelCorporateAccount.exists?(hotel_id: hotel_id, agent_code: agent_code)
    end
  end
end
