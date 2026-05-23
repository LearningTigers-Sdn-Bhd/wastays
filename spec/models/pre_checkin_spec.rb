require 'rails_helper'

RSpec.describe PreCheckin, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:booking) }
  end

  describe 'validations' do
    subject(:pre_checkin) { create(:pre_checkin) }

    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:token) }
    it { is_expected.to validate_uniqueness_of(:token) }
    it { is_expected.to validate_uniqueness_of(:booking_id) }
  end

  describe 'callbacks' do
    it 'generates token on create when missing' do
      pre_checkin = create(:pre_checkin, token: nil)

      expect(pre_checkin.token).to be_present
    end
  end

  describe '#completed?' do
    it 'returns true when status is completed' do
      expect(build(:pre_checkin, status: 'completed').completed?).to be(true)
    end

    it 'returns false when status is not completed' do
      expect(build(:pre_checkin, status: 'pending').completed?).to be(false)
    end
  end
end
