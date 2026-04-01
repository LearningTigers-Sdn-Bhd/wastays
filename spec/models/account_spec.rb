require 'rails_helper'

RSpec.describe Account, type: :model do
  describe 'associations' do
    it { should have_many(:users).dependent(:destroy) }
    it { should have_many(:hotels).dependent(:destroy) }
    it { should have_one(:banking_detail).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:account) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:status) }

    it 'generates a slug from name on create' do
      account = create(:account, name: 'Green Hotel Group', slug: nil)
      expect(account.slug).to eq('green-hotel-group')
    end

    it 'validates uniqueness of slug' do
      create(:account, name: 'First Account', slug: 'first-account')
      duplicate = build(:account, name: 'Second Account', slug: 'first-account')
      expect(duplicate).not_to be_valid
    end
  end

  describe 'constants' do
    it 'defines allowed statuses' do
      expect(Account::STATUSES).to match_array(%w[active suspended pending_review])
    end
  end
end
