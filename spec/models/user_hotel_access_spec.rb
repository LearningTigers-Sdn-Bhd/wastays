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

  describe 'account management' do
    let(:account) { create(:account) }
    let(:hotel) { create(:hotel, account: account) }
    let(:manage_account) do
      Permission.find_by(slug: 'manage_account') || create(:permission, slug: 'manage_account', name: 'Manage Account')
    end
    let(:owner_role) do
      role = create(:role, account: account, name: 'Owner', slug: 'owner')
      role.permissions << manage_account
      role
    end
    let(:staff_role) { create(:role, account: account, name: 'Front Desk', slug: 'front_desk') }

    def access_for(role, deactivated_at: nil)
      UserHotelAccess.create!(
        user: create(:user, account: account),
        hotel: hotel,
        role: role,
        deactivated_at: deactivated_at
      )
    end

    describe '#manages_account?' do
      it 'is true when the role carries the permission' do
        expect(access_for(owner_role).manages_account?).to be true
      end

      it 'is false otherwise' do
        expect(access_for(staff_role).manages_account?).to be false
      end
    end

    describe '#sole_account_manager?' do
      it 'is true for the only active account manager' do
        owner = access_for(owner_role)
        access_for(staff_role)

        expect(owner.sole_account_manager?).to be true
      end

      it 'is false once a second account manager exists' do
        owner = access_for(owner_role)
        access_for(owner_role)

        expect(owner.sole_account_manager?).to be false
      end

      it 'ignores deactivated account managers when counting' do
        owner = access_for(owner_role)
        access_for(owner_role, deactivated_at: Time.current)

        expect(owner.sole_account_manager?).to be true
      end

      it 'is false for an access that is already deactivated' do
        owner = access_for(owner_role, deactivated_at: Time.current)

        expect(owner.sole_account_manager?).to be false
      end

      it 'is false for a role without account management' do
        expect(access_for(staff_role).sole_account_manager?).to be false
      end
    end

    describe '.in_directory_order' do
      it 'lists active access before revoked access' do
        revoked = access_for(staff_role, deactivated_at: Time.current)
        active = access_for(staff_role)

        expect(hotel.user_hotel_accesses.in_directory_order.to_a).to eq([ active, revoked ])
      end
    end
  end
end
