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

  describe 'boat transfer fields and validations' do
    subject(:booking_guest) { build(:booking_guest) }

    describe '#boat_in?' do
      it 'returns true if boat_in_at is set' do
        booking_guest.boat_in_at = Time.current
        expect(booking_guest.boat_in?).to be(true)
      end

      it 'returns false if boat_in_at is nil' do
        booking_guest.boat_in_at = nil
        expect(booking_guest.boat_in?).to be(false)
      end
    end

    describe '#boat_out?' do
      it 'returns true if boat_out_at is set' do
        booking_guest.boat_out_at = Time.current
        expect(booking_guest.boat_out?).to be(true)
      end

      it 'returns false if boat_out_at is nil' do
        booking_guest.boat_out_at = nil
        expect(booking_guest.boat_out?).to be(false)
      end
    end

    describe 'boat_out_after_boat_in validation' do
      it 'is valid if boat_out_at is after boat_in_at' do
        booking_guest.boat_in_at = 2.hours.ago
        booking_guest.boat_out_at = 1.hour.ago
        expect(booking_guest).to be_valid
      end

      it 'is invalid if boat_out_at is before boat_in_at' do
        booking_guest.boat_in_at = 1.hour.ago
        booking_guest.boat_out_at = 2.hours.ago
        expect(booking_guest).not_to be_valid
        expect(booking_guest.errors[:boat_out_at]).to include('must be after boat in time')
      end

      it 'is valid if only one of them is set' do
        booking_guest.boat_in_at = Time.current
        booking_guest.boat_out_at = nil
        expect(booking_guest).to be_valid

        booking_guest.boat_in_at = nil
        booking_guest.boat_out_at = Time.current
        expect(booking_guest).to be_valid
      end
    end
  end

  describe 'guest snapshot capture' do
    it 'does not raise and leaves the snapshot blank when a guest field is undecryptable under the current key' do
      guest = create(:guest, email: 'jane@example.com', phone: '+60111111111', government_id: 'A123456')
      quoted = Guest.connection.quote('{"p":"corrupted","h":{"iv":"bogus","at":"bogus"}}')
      Guest.connection.execute("UPDATE guests SET email = #{quoted} WHERE id = #{guest.id}")
      guest.reload
      booking = create(:booking)

      booking_guest = nil
      expect { booking_guest = create(:booking_guest, booking: booking, guest: guest, is_primary: true) }.not_to raise_error

      expect(booking_guest.email_snapshot).to be_nil
      expect(booking_guest.phone_snapshot).to eq('+60111111111')
    end
  end
end
