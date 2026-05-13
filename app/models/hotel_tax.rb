# frozen_string_literal: true

class HotelTax < ApplicationRecord
  belongs_to :hotel

  RATE_TYPES = %w[flat percentage].freeze

  validates :name, presence: true
  validates :rate_type, inclusion: { in: RATE_TYPES }
  validates :amount, presence: true, numericality: { greater_than: 0 }

  scope :enabled, -> { where(enabled: true) }

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
end
