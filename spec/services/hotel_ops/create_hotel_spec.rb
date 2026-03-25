require 'rails_helper'

RSpec.describe HotelOps::CreateHotel do
  let(:account_params) { { name: 'Green Hotel Group' } }
  let(:user_params) { { name: 'Sarah Lim', email: 'sarah@example.com', password: 'password' } }
  let(:hotel_params) { { name: 'Green Hotel KL', city: 'Kuala Lumpur', country: 'Malaysia' } }

  subject { described_class.new(account_params: account_params, user_params: user_params, hotel_params: hotel_params) }

  before do
    # Ensure permissions are seeded
    Permission.find_or_create_by!(slug: 'manage_account') { |p| p.name = 'Manage Account' }
  end

  describe '#call' do
    context 'with valid params' do
      it 'creates an account, user, and hotel' do
        expect {
          result = subject.call
          expect(result[:success]).to be true
        }.to change(Account, :count).by(1)
         .and change(User, :count).by(1)
         .and change(Hotel, :count).by(1)
      end

      it 'seeds roles for the account' do
        result = subject.call
        account = result[:account]
        expect(account.roles.count).to be > 0
        expect(account.roles.pluck(:slug)).to include('hotel_owner')
      end

      it 'assigns the owner role to the user' do
        result = subject.call
        user = result[:user]
        expect(user.roles.pluck(:slug)).to include('hotel_owner')
      end

      it 'sets up hotel access for the user' do
        result = subject.call
        user = result[:user]
        hotel = result[:hotel]
        expect(user.hotels).to include(hotel)
        expect(user.user_hotel_accesses.first.role.slug).to eq('hotel_owner')
      end
    end

    context 'with invalid params' do
      let(:user_params) { { name: '', email: 'invalid', password: '' } }

      it 'returns success false and does not create records' do
        expect {
          result = subject.call
          expect(result[:success]).to be false
          expect(result[:error]).to be_present
        }.not_to change(Account, :count)
      end
    end
  end
end
