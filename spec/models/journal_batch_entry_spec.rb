require 'rails_helper'

RSpec.describe JournalBatchEntry, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:journal_batch) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:gl_code) }
    it { is_expected.to validate_presence_of(:transaction_type) }
    it { is_expected.to validate_numericality_of(:debit_amount) }
    it { is_expected.to validate_numericality_of(:credit_amount) }
  end
end
