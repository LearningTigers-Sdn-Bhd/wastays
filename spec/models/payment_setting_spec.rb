require 'rails_helper'

RSpec.describe PaymentSetting, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:settable) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:gateway) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe 'scopes' do
    it 'returns only active payment settings' do
      active_setting = create(:payment_setting, status: 'active')
      create(:payment_setting, status: 'inactive')

      expect(described_class.active).to contain_exactly(active_setting)
    end
  end
end
