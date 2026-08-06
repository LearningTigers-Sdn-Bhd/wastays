# frozen_string_literal: true

class HotelTax < ApplicationRecord
  belongs_to :hotel
  belongs_to :transaction_code, optional: true
  has_many :transaction_code_taxes, dependent: :destroy
  has_many :taxable_transaction_codes, through: :transaction_code_taxes, source: :transaction_code

  RATE_TYPES = %w[flat percentage].freeze
  CHARGE_TYPES = %w[tax charge others].freeze

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :hotel_id }
  validates :rate_type, inclusion: { in: RATE_TYPES }
  validates :charge_type, inclusion: { in: CHARGE_TYPES }
  validates :amount, presence: true, numericality: { greater_than: 0 }

  scope :enabled, -> { where(enabled: true) }

  before_validation :normalize_code
  after_create :ensure_transaction_code
  after_update :sync_transaction_code, if: :saved_change_to_transaction_code_fields?

  def applicable_for?(guest_country)
    return false unless enabled?
    return false if foreign_guests_only && guest_country.to_s.casecmp("Malaysia").zero?
    true
  end

  def compute(rooms_subtotal:)
    return amount.to_f if rate_type == "flat"

    (rooms_subtotal * amount / 100.0).round(2)
  end

  def to_tax_line(rooms_subtotal:)
    {
      "name"   => name,
      "amount" => compute(rooms_subtotal: rooms_subtotal),
      "type"   => "custom"
    }
  end

  def transaction_code_value(value = code)
    charge_type == "tax" ? "TAX_#{value}" : value
  end

  def ensure_transaction_code
    return transaction_code if transaction_code.present?

    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = create_transaction_code
    update_column(:transaction_code_id, code.id)
    self.transaction_code = code
    transaction_code
  end

  private

  def create_transaction_code
    base_code = code
    suffix = 1

    loop do
      candidate_code = suffix == 1 ? base_code : "#{base_code}#{suffix}"
      update_column(:code, candidate_code) if candidate_code != code

      return hotel.transaction_codes.create!(
        system_key: "hotel_tax_#{id}",
        code: transaction_code_value(candidate_code),
        name: name,
        kind: transaction_code_kind,
        category: transaction_code_category,
        active: enabled?,
        system_required: false,
        gl_account_code: hotel.transaction_codes.find_by(system_key: "sst_tax")&.gl_account_code ||
          hotel.hotel_general_ledger_maps.find_by(transaction_category: "tax")&.gl_code
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      existing_code = hotel.transaction_codes.find_by(system_key: "hotel_tax_#{id}")
      return existing_code if existing_code.present?

      suffix += 1
      retry
    end
  end

  def normalize_code
    normalized = normalized_code(code.presence || code_abbreviation_from_name)
    self.code = hotel.present? ? unique_code(normalized) : normalized.presence
  end

  def unique_code(base_code)
    base_code = "CUSTOM" if base_code.blank?
    candidate = base_code
    suffix = 2

    while code_taken?(candidate)
      candidate = "#{base_code}#{suffix}"
      suffix += 1
    end

    candidate
  end

  def code_taken?(candidate)
    hotel.hotel_taxes.where(code: candidate).where.not(id: id).exists? ||
      hotel.transaction_codes.where(code: transaction_code_value(candidate)).where.not(id: transaction_code_id).exists?
  end

  def normalized_code(value)
    value.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
  end

  def code_abbreviation_from_name
    words = name.to_s.scan(/[A-Za-z0-9]+/)
    abbreviation = if words.length > 1
      words.map { |word| word[0] }.join
    else
      words.first.to_s[0, 4]
    end

    abbreviation.upcase.presence || "CUSTOM"
  end

  def transaction_code_kind
    charge_type == "tax" ? "tax" : "charge"
  end

  def transaction_code_category
    charge_type == "tax" ? "tax" : "other"
  end

  def saved_change_to_transaction_code_fields?
    saved_change_to_enabled? || saved_change_to_code? || saved_change_to_name? || saved_change_to_charge_type?
  end

  def sync_transaction_code
    ensure_transaction_code.update!(
      active: enabled?,
      code: transaction_code_value,
      name: name,
      kind: transaction_code_kind,
      category: transaction_code_category
    )
  end
end
