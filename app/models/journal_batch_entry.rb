class JournalBatchEntry < ApplicationRecord
  belongs_to :journal_batch

  validates :gl_code, presence: true
  validates :transaction_type, presence: true
  validates :debit_amount, numericality: true
  validates :credit_amount, numericality: true
end
