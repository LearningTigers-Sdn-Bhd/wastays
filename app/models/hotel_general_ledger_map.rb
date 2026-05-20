class HotelGeneralLedgerMap < ApplicationRecord
  belongs_to :hotel

  validates :transaction_category, presence: true, uniqueness: { scope: :hotel_id }
  validates :gl_code, presence: true

  validates :transaction_category, inclusion: {
    in: FolioTransaction::CHARGE_CATEGORIES +
        FolioTransaction::PAYMENT_CATEGORIES +
        FolioTransaction::ADJUSTMENT_CATEGORIES,
    message: "%{value} is not a valid transaction category"
  }
end
