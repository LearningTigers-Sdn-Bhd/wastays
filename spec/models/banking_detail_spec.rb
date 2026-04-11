require 'rails_helper'

RSpec.describe BankingDetail, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
  end

  describe 'validations' do
    subject(:banking_detail) { build(:banking_detail) }

    it { should validate_presence_of(:account_holder_name) }
    it { should validate_presence_of(:bank_name) }
    it { should validate_presence_of(:account_number) }

    it { should allow_value('5142 1234 5678').for(:account_number) }
    it { should allow_value('A-12345-678').for(:account_number) }
    it { should_not allow_value('1234/5678').for(:account_number) }
  end

  describe 'before_validation' do
    it 'strips surrounding whitespace from text fields' do
      banking_detail = build(
        :banking_detail,
        account_holder_name: '  Syarikat Maju Jaya Sdn Bhd  ',
        bank_name: '  Maybank  ',
        account_number: '  5142 1234 5678  '
      )

      banking_detail.valid?

      expect(banking_detail.account_holder_name).to eq('Syarikat Maju Jaya Sdn Bhd')
      expect(banking_detail.bank_name).to eq('Maybank')
      expect(banking_detail.account_number).to eq('5142 1234 5678')
    end
  end
end
