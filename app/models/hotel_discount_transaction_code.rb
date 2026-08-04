# frozen_string_literal: true

class HotelDiscountTransactionCode < ApplicationRecord
  belongs_to :hotel_discount
  belongs_to :transaction_code

  validates :transaction_code_id, uniqueness: { scope: :hotel_discount_id }
  validate :transaction_code_is_available_charge

  private

  def transaction_code_is_available_charge
    return if hotel_discount.blank? || transaction_code.blank?
    return if transaction_code.hotel_id == hotel_discount.hotel_id && transaction_code.kind == "charge" && transaction_code.category != "tax"

    errors.add(:transaction_code, "must be a non-tax charge code from the same hotel")
  end
end
