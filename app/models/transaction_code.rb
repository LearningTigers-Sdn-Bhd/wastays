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
  has_many :ota_financial_components, dependent: :restrict_with_error
  has_many :ota_financial_component_mappings, dependent: :restrict_with_error
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
  # What a discount is allowed to target. Mirrors the rule
  # HotelDiscountTransactionCode enforces on the join row, so the picker cannot
  # offer a code the join would then reject.
  scope :discountable, -> { charge.where.not(category: "tax") }
  # The room and what the booking engine posts against it: the rate itself, and
  # the charges a stay's own shape produces. A discount reaches these through
  # its room-charges scope, which follows any accommodation code the property
  # adds later, so naming them one at a time in a picker says the same thing
  # worse. Extra charges holds the same codes out of reach for the matching
  # reason — they are posted, not sold.
  ROOM_CATEGORIES = %w[
    accommodation no_show_charge cancellation_charge late_checkout_charge early_departure_charge
  ].freeze

  scope :room_related, -> { where(category: ROOM_CATEGORIES) }

  def hotel_tax_ids
    tax_ids
  end

  def tax_rule_keys
    transaction_code_taxes.map(&:tax_rule_key)
  end
end
