require 'rails_helper'

RSpec.describe Role, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account).optional }
    it { is_expected.to have_many(:role_permissions).dependent(:destroy) }
    it { is_expected.to have_many(:permissions).through(:role_permissions) }
    it { is_expected.to have_many(:user_roles).dependent(:destroy) }
    it { is_expected.to have_many(:users).through(:user_roles) }
    it { is_expected.to have_many(:user_hotel_accesses).dependent(:restrict_with_error) }
  end

  describe 'validations' do
    subject(:role) { create(:role) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:slug).scoped_to(:account_id) }
  end

  describe 'callbacks' do
    it 'generates slug from name when missing' do
      role = create(:role, name: 'Revenue Manager', slug: nil)

      expect(role.slug).to eq('revenue-manager')
    end
  end
end
