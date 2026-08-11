# frozen_string_literal: true

class HotelPaymentMethod < ApplicationRecord
  PAYMENT_METHOD_TYPES = %w[cash bank_gateway].freeze
  SURCHARGE_POSTING_TYPES = %w[fixed percentage].freeze

  belongs_to :hotel
  belongs_to :transaction_code
  belongs_to :surcharge_extra_charge, class_name: "HotelExtraCharge", optional: true
  has_many :channel_settlement_receipts, dependent: :restrict_with_error

  delegate :name, :name=, :code, :code=, :active, :active=, to: :transaction_code

  validates :transaction_code_id, uniqueness: true
  validates :payment_method_type, inclusion: { in: PAYMENT_METHOD_TYPES }
  validates :surcharge_posting_type, inclusion: { in: SURCHARGE_POSTING_TYPES }, allow_nil: true
  validates :surcharge_value, numericality: { greater_than: 0 }, allow_nil: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :transaction_code_belongs_to_hotel
  validate :transaction_code_is_payment
  validate :transaction_code_code_is_short
  validate :default_cash_is_direct_cash
  validate :surcharge_configuration_is_complete
  validate :percentage_surcharge_is_valid
  validate :surcharge_extra_charge_is_available

  scope :active, -> { joins(:transaction_code).merge(TransactionCode.active) }
  scope :ordered, -> { order(:position, :id) }

  def active? = transaction_code.active?
  def cash? = payment_method_type == "cash"
  def bank_gateway? = payment_method_type == "bank_gateway"
  def surcharge? = surcharge_posting_type.present?
  def fixed_surcharge? = surcharge_posting_type == "fixed"
  def percentage_surcharge? = surcharge_posting_type == "percentage"

  def expected_category
    return "booking_payment" if guest_advance?

    cash? ? "cash" : "gateway_payment"
  end

  def surcharge_amount(base_amount)
    return 0.to_d unless surcharge?

    amount = fixed_surcharge? ? surcharge_value.to_d : base_amount.to_d * surcharge_value.to_d / 100
    amount.round(2)
  end

  def surcharge_label(currency = hotel.default_currency)
    return "None" unless surcharge?
    return "#{surcharge_value.to_d.to_s('F')}%" if percentage_surcharge?

    "#{currency} #{format('%.2f', surcharge_value.to_d)}"
  end

  private

  def transaction_code_belongs_to_hotel
    return if hotel.blank? || transaction_code.blank? || transaction_code.hotel_id == hotel_id

    errors.add(:transaction_code, "must belong to the same hotel")
  end

  def transaction_code_is_payment
    return if transaction_code.blank? || transaction_code.kind == "payment"

    errors.add(:transaction_code, "must be a payment code")
  end

  def transaction_code_code_is_short
    return if transaction_code.blank? || transaction_code.code.to_s.length <= 10

    errors.add(:code, "must be 10 characters or fewer")
  end

  def default_cash_is_direct_cash
    return unless default_cash?

    unless cash? && !guest_advance?
      errors.add(:default_cash, "is only available for direct cash payment methods")
      return
    end
    return if transaction_code&.active?

    errors.add(:default_cash, "must remain active")
  end

  def surcharge_configuration_is_complete
    fields = [ surcharge_posting_type, surcharge_value, surcharge_extra_charge_id ]
    return if fields.all?(&:blank?) || fields.all?(&:present?)

    errors.add(:base, "Surcharge type, value, and extra charge must be configured together")
  end

  def percentage_surcharge_is_valid
    return unless percentage_surcharge? && surcharge_value.present? && surcharge_value.to_d > 100

    errors.add(:surcharge_value, "must be 100 or less for percentage surcharges")
  end

  def surcharge_extra_charge_is_available
    return if surcharge_extra_charge.blank?

    if surcharge_extra_charge.hotel_id != hotel_id
      errors.add(:surcharge_extra_charge, "must belong to the same hotel")
    elsif !surcharge_extra_charge.active? || surcharge_extra_charge.transaction_code.kind != "charge"
      errors.add(:surcharge_extra_charge, "must be an active extra charge")
    end
  end
end
