require 'rails_helper'

RSpec.describe BookingGuest, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:booking) }
    it { is_expected.to belong_to(:guest) }
  end

  describe 'validations' do
    subject(:booking_guest) { build(:booking_guest) }

    it 'requires is_primary to be true or false' do
      booking_guest.is_primary = nil
      expect(booking_guest).not_to be_valid
      expect(booking_guest.errors[:is_primary]).to include('is not included in the list')
    end
  end
end
