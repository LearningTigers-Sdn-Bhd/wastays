require 'rails_helper'

RSpec.describe Permission, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:role_permissions).dependent(:destroy) }
    it { is_expected.to have_many(:roles).through(:role_permissions) }
  end

  describe 'validations' do
    subject(:permission) { create(:permission) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:slug) }
  end

  describe 'callbacks' do
    it 'generates slug from name on create when missing' do
      permission = create(:permission, name: 'Manage Rates', slug: nil)

      expect(permission.slug).to eq('manage-rates')
    end
  end
end
