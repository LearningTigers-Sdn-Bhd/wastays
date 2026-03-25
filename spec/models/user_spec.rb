require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_many(:user_hotel_accesses).dependent(:destroy) }
    it { should have_many(:hotels).through(:user_hotel_accesses) }
  end

  describe 'validations' do
    subject { build(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email) }
    it { should allow_value('test@example.com').for(:email) }
    it { should_not allow_value('invalid-email').for(:email) }
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:role) }
  end

  describe 'roles' do
    it 'defines allowed roles' do
      expect(User::ROLES).to match_array(%w[superadmin admin hotel_staff])
    end

    describe '#superadmin?' do
      it 'returns true if role is superadmin' do
        user = build(:user, role: 'superadmin')
        expect(user.superadmin?).to be true
      end

      it 'returns false if role is not superadmin' do
        user = build(:user, role: 'admin')
        expect(user.superadmin?).to be false
      end
    end

    describe '#admin?' do
      it 'returns true if role is admin' do
        user = build(:user, role: 'admin')
        expect(user.admin?).to be true
      end

      it 'returns false if role is not admin' do
        user = build(:user, role: 'hotel_staff')
        expect(user.admin?).to be false
      end
    end
  end
end
