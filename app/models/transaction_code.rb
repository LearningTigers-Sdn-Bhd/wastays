# frozen_string_literal: true

class TransactionCode < ApplicationRecord
  KINDS = %w[charge payment adjustment tax].freeze
  CATEGORIES = %w[
    accommodation
    no_show_charge
    cancellation_charge
    late_checkout_charge
    early_departure_charge
    tax
    fb
    parking
    other
    cash
    gateway_payment
    booking_payment
    security_deposit
    refund
    adjustment
    correction
    discount
    write_off
  ].freeze

  belongs_to :hotel
  has_many :folio_transactions, dependent: :nullify
  has_many :deposits, dependent: :restrict_with_error
  has_many :folio_routing_rules, dependent: :restrict_with_error
  has_many :hotel_taxes, dependent: :nullify
  has_many :transaction_code_taxes, dependent: :destroy
  has_many :taxes, through: :transaction_code_taxes, source: :hotel_tax
  has_one :hotel_extra_charge, dependent: :restrict_with_error
  has_one :hotel_discount, dependent: :restrict_with_error
  has_one :hotel_reservation_policy, dependent: :restrict_with_error
  has_one :hotel_payment_method, dependent: :restrict_with_error

  validates :system_key, :code, :name, :kind, :category, presence: true
  validates :system_key, uniqueness: { scope: :hotel_id }
  validates :code, uniqueness: { scope: :hotel_id }
  validates :kind, inclusion: { in: KINDS }
  validates :category, inclusion: { in: CATEGORIES }

  scope :active, -> { where(active: true) }
  scope :system_required, -> { where(system_required: true) }
  scope :charge, -> { where(kind: "charge") }

  def hotel_tax_ids
    tax_ids
  end

  def tax_rule_keys
    transaction_code_taxes.map(&:tax_rule_key)
  end
end
