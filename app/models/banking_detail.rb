class BankingDetail < ApplicationRecord
  belongs_to :account

  ACCOUNT_NUMBER_FORMAT = /\A[\p{Alnum}\s-]+\z/

  validates :account_holder_name, presence: true, length: { maximum: 255 }
  validates :bank_name, presence: true, length: { maximum: 255 }
  validates :account_number, presence: true, length: { maximum: 34 }, format: { with: ACCOUNT_NUMBER_FORMAT }

  before_validation :strip_fields

  private

  def strip_fields
    self.account_holder_name = account_holder_name&.strip
    self.bank_name = bank_name&.strip
    self.account_number = account_number&.strip
  end
end
