# frozen_string_literal: true

class TransactionCodeTax < ApplicationRecord
  belongs_to :transaction_code
  belongs_to :hotel_tax

  validate :hotel_tax_belongs_to_same_hotel

  private

  def hotel_tax_belongs_to_same_hotel
    return if transaction_code.blank? || hotel_tax.blank?
    return if transaction_code.hotel_id == hotel_tax.hotel_id

    errors.add(:hotel_tax, "must belong to the same hotel as the transaction code")
  end
end
