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
  end

  describe 'normalization' do
    it 'normalizes gender, document_type and country before validation' do
      record = build(:guest, gender: 'FEMALE', document_type: 'PASSPORT', country: 'united states')

      record.validate

      expect(record.gender).to eq('female')
      expect(record.document_type).to eq('passport')
      expect(record.country).to eq('United States')
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
end
