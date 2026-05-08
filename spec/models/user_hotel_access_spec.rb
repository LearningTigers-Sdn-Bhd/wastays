require 'rails_helper'

RSpec.describe UserHotelAccess, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:hotel) }
    it { should belong_to(:role) }
  end

  describe 'validations' do
    subject { create(:user_hotel_access) }
    it { should validate_uniqueness_of(:user_id).scoped_to(:hotel_id) }
  end

  describe 'scopes' do
    let!(:active_access) { create(:user_hotel_access, deactivated_at: nil) }
    let!(:deactivated_access) { create(:user_hotel_access, deactivated_at: Time.current) }

    describe '.active' do
      it 'returns only active accesses' do
        expect(UserHotelAccess.active).to include(active_access)
        expect(UserHotelAccess.active).not_to include(deactivated_access)
      end
    end

    describe '.deactivated' do
      it 'returns only deactivated accesses' do
        expect(UserHotelAccess.deactivated).to include(deactivated_access)
        expect(UserHotelAccess.deactivated).not_to include(active_access)
      end
    end
  end

  describe 'instance methods' do
    let(:access) { create(:user_hotel_access) }

    describe '#active?' do
      it 'returns true if deactivated_at is nil' do
        access.deactivated_at = nil
        expect(access.active?).to be true
      end

      it 'returns false if deactivated_at is present' do
        access.deactivated_at = Time.current
        expect(access.active?).to be false
      end
    end

    describe '#deactivate!' do
      it 'sets deactivated_at' do
        expect { access.deactivate! }.to change { access.deactivated_at }.from(nil)
      end
    end

    describe '#reactivate!' do
      it 'clears deactivated_at' do
        access.deactivate!
        expect { access.reactivate! }.to change { access.deactivated_at }.to(nil)
      end
    end
  end
end
