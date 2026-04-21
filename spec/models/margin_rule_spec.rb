require 'rails_helper'

RSpec.describe MarginRule, type: :model do
  subject(:margin_rule) { build(:margin_rule) }

  describe 'associations' do
    it { is_expected.to belong_to(:settable).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:rate) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_numericality_of(:rate).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
  end

  describe 'scopes' do
    it 'returns only active rules' do
      active_rule = create(:margin_rule, status: 'active')
      create(:margin_rule, status: 'inactive')

      expect(described_class.active).to contain_exactly(active_rule)
    end
  end

  describe 'normalization' do
    it 'normalizes blank settable fields to nil before validation' do
      record = described_class.new(rate: 10, status: 'active', settable_type: '', settable_id: '')

      record.validate

      expect(record.settable_type).to be_nil
      expect(record.settable_id).to be_nil
    end
  end
end
