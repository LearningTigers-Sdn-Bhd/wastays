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

  describe 'VIP synchronization' do
    let(:vip_guest) { create(:guest, vip: true) }
    let(:regular_guest) { create(:guest, vip: false) }
    let(:booking) { create(:booking) }

    it 'marks the booking as VIP when a VIP guest is associated' do
      create(:booking_guest, booking: booking, guest: vip_guest, is_primary: true)
      expect(booking.reload.vip).to be(true)
    end

    it 'does not mark the booking as VIP when a non-VIP guest is associated' do
      create(:booking_guest, booking: booking, guest: regular_guest, is_primary: true)
      expect(booking.reload.vip).to be(false)
    end
  end
end
