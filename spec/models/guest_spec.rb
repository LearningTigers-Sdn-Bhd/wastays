require 'rails_helper'

RSpec.describe Guest, type: :model do
  subject(:guest) { build(:guest) }

  describe 'associations' do
    it { is_expected.to have_many(:booking_guests).dependent(:destroy) }
    it { is_expected.to have_many(:bookings).through(:booking_guests) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:country) }
    it { is_expected.to allow_value('male', 'female', 'other').for(:gender) }
    it { is_expected.not_to allow_value('unknown').for(:gender) }
    it { is_expected.to allow_value('ic', 'passport', nil).for(:document_type) }
    it { is_expected.not_to allow_value('license').for(:document_type) }

    it 'allows a past date_of_birth' do
      record = build(:guest, date_of_birth: Date.new(1990, 1, 1))

      expect(record).to be_valid
    end

    it 'allows a blank date_of_birth for Malaysian IC guests' do
      record = build(:guest, date_of_birth: nil, country: 'Malaysia', document_type: 'ic', government_id: nil)

      expect(record).to be_valid
    end

    it 'requires date_of_birth for reporting guests who are non-Malaysian' do
      record = build(:guest, date_of_birth: nil, country: 'Singapore', document_type: 'ic')

      record.validate

      expect(record.errors[:date_of_birth]).to include('is required for passport guests')
    end

    it 'requires date_of_birth for passport guests' do
      record = build(:guest, date_of_birth: nil, country: 'Malaysia', document_type: 'passport')

      record.validate

      expect(record.errors[:date_of_birth]).to include('is required for passport guests')
    end

    it 'rejects date_of_birth on or after today' do
      record = build(:guest, date_of_birth: Date.current)

      record.validate

      expect(record.errors[:date_of_birth]).to include('must be in the past')
    end

    it 'allows a valid past date_of_birth' do
      record = build(:guest, date_of_birth: Date.current - 1.day)

      record.validate

      expect(record.errors[:date_of_birth]).to be_empty
    end
  end

  describe 'normalization' do
    it 'normalizes gender, document_type and country before validation' do
      record = build(:guest, gender: 'FEMALE', document_type: 'PASSPORT', country: 'united states')

      record.validate

      expect(record.gender).to eq('female')
      expect(record.document_type).to eq('passport')
      expect(record.country).to eq('United States')
    end

    it 'autofills date_of_birth from a Malaysian IC when blank' do
      record = build(:guest, country: 'Malaysia', document_type: 'ic', government_id: '010203-10-1234', date_of_birth: nil)

      record.validate

      expect(record.date_of_birth).to eq(Date.new(2001, 2, 3))
    end

    it 'does not overwrite a manually provided date_of_birth' do
      record = build(:guest, country: 'Malaysia', document_type: 'ic', government_id: '010203-10-1234', date_of_birth: Date.new(1999, 12, 31))

      record.validate

      expect(record.date_of_birth).to eq(Date.new(1999, 12, 31))
    end
  end

  describe 'otp methods' do
    let(:record) { create(:guest) }

    it 'generates and verifies otp' do
      code = record.generate_otp!

      expect(code.length).to eq(Guest::OTP_LENGTH)
      expect(record.verify_otp(code)).to be(true)
      expect(record.verify_otp('000000')).to be(false)
    end

    it 'rejects expired otp codes' do
      code = record.generate_otp!
      record.update_column(:otp_sent_at, (Guest::OTP_EXPIRY + 1.minute).ago)

      expect(record.verify_otp(code)).to be(false)
    end

    it 'tracks otp cooldown' do
      record.update_column(:otp_sent_at, 1.minute.ago)
      expect(record.otp_on_cooldown?).to be(true)

      record.update_column(:otp_sent_at, 3.minutes.ago)
      expect(record.otp_on_cooldown?).to be(false)
    end

    it 'consumes otp and records sign in time' do
      record.generate_otp!

      expect { record.consume_otp! }
        .to change(record, :last_signed_in_at).from(nil)

      expect(record.otp_code_digest).to be_nil
      expect(record.otp_sent_at).to be_nil
    end
  end

  describe 'magic link methods' do
    let(:record) { create(:guest) }

    it 'generates and verifies magic token' do
      token = record.generate_magic_token!

      expect(record.verify_magic_token(token)).to be(true)
      expect(record.verify_magic_token('invalid-token')).to be(false)
    end

    it 'rejects expired magic token' do
      token = record.generate_magic_token!
      record.update_column(:magic_token_expires_at, 1.minute.ago)

      expect(record.verify_magic_token(token)).to be(false)
    end

    it 'consumes magic token and records sign in time' do
      record.generate_magic_token!

      expect { record.consume_magic_token! }
        .to change(record, :last_signed_in_at).from(nil)

      expect(record.magic_token_digest).to be_nil
      expect(record.magic_token_expires_at).to be_nil
    end
  end

  describe 'VIP propagation' do
    let(:guest) { create(:guest, vip: false) }
    let(:booking1) { create(:booking) }
    let(:booking2) { create(:booking) }

    before do
      create(:booking_guest, booking: booking1, guest: guest, is_primary: true)
      create(:booking_guest, booking: booking2, guest: guest, is_primary: false)
    end

    it 'propagates VIP status to all bookings when marked as VIP' do
      expect { guest.update!(vip: true) }
        .to change { booking1.reload.vip }.from(false).to(true)
        .and change { booking2.reload.vip }.from(false).to(true)
    end

    it 'propagates non-VIP status to all bookings when VIP status is removed' do
      guest.update!(vip: true)
      expect(booking1.reload.vip).to be(true)
      expect(booking2.reload.vip).to be(true)

      expect { guest.update!(vip: false) }
        .to change { booking1.reload.vip }.from(true).to(false)
        .and change { booking2.reload.vip }.from(true).to(false)
    end
  end

  describe 'blacklisted?' do
    let!(:banned_guest) { create(:guest, name: "John Doe", email: "john@example.com", blacklisted: true) }
    let!(:regular_guest) { create(:guest, name: "Jane Smith", email: "jane@example.com", blacklisted: false) }

    it 'returns true if the email matches a blacklisted guest' do
      expect(Guest.blacklisted?(email: "john@example.com")).to be(true)
      expect(Guest.blacklisted?(email: "JOHN@EXAMPLE.COM")).to be(true)
    end

    it 'returns true if the name matches a blacklisted guest case-insensitively' do
      expect(Guest.blacklisted?(name: "John Doe")).to be(true)
      expect(Guest.blacklisted?(name: "john doe")).to be(true)
    end

    it 'returns false if the email/name matches a non-blacklisted guest' do
      expect(Guest.blacklisted?(email: "jane@example.com")).to be(false)
      expect(Guest.blacklisted?(name: "Jane Smith")).to be(false)
    end

    it 'returns false for unmatched email or name' do
      expect(Guest.blacklisted?(email: "other@example.com")).to be(false)
      expect(Guest.blacklisted?(name: "Other Guest")).to be(false)
    end

    context 'with hotel-scoped blacklisting' do
      let(:hotel_a) { create(:hotel) }
      let(:hotel_b) { create(:hotel) }
      let!(:scoped_guest) do
        create(:guest, name: "Scoped Guest", email: "scoped@example.com", blacklisted: true, metadata: {
          "blacklisted_hotel_ids" => [ hotel_a.id ]
        })
      end

      it 'returns true for blacklisted_at? at hotel A' do
        expect(scoped_guest.blacklisted_at?(hotel_a)).to be(true)
      end

      it 'returns false for blacklisted_at? at hotel B' do
        expect(scoped_guest.blacklisted_at?(hotel_b)).to be(false)
      end

      it 'respects hotel scoping in Guest.blacklisted? class method' do
        expect(Guest.blacklisted?(email: "scoped@example.com", hotel: hotel_a)).to be(true)
        expect(Guest.blacklisted?(email: "scoped@example.com", hotel: hotel_b)).to be(false)
      end

      it 'respects hotel scoping in Guest.banned? class method' do
        expect(Guest.banned?(email: "scoped@example.com", hotel: hotel_a)).to be(true)
        expect(Guest.banned?(email: "scoped@example.com", hotel: hotel_b)).to be(false)
      end
    end
  end

  describe 'repeat?' do
    let(:guest) { create(:guest) }
    let(:booking) { create(:booking) }

    it 'returns false if there are no completed bookings' do
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      booking.update_columns(status: 'confirmed', check_in: Date.current, check_out: Date.current + 2)
      expect(guest.repeat?).to be(false)
      expect(booking.repeat?).to be(false)
    end

    it 'returns true if there is at least one completed booking and want to book again' do
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      booking.update_columns(status: 'completed', check_in: 3.days.ago, check_out: 2.days.ago)

      expect(guest.repeat?).to be(false) # only 1 completed booking, no second booking yet
      expect(booking.repeat?).to be(false) # first booking itself is not a repeat booking

      second_booking = create(:booking)
      create(:booking_guest, booking: second_booking, guest: guest, is_primary: true)
      second_booking.update_columns(status: 'confirmed', check_in: 1.day.ago, check_out: Date.current)

      expect(guest.repeat?).to be(true) # now has second booking
      expect(second_booking.repeat?).to be(true) # second booking is a repeat booking
    end
  end
end
