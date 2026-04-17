require 'rails_helper'

RSpec.describe Hotel, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_many(:user_hotel_accesses).dependent(:destroy) }
    it { should have_many(:users).through(:user_hotel_accesses) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:city) }
    it { should validate_presence_of(:country) }
  end

  describe 'constants' do
    it 'defines allowed statuses' do
      expect(Hotel::STATUSES).to match_array(%w[
        registered
        email_verified
        profile_incomplete
        rooms_incomplete
        inventory_incomplete
        pending_review
        approved
        live
        suspended
      ])
    end
  end

  describe '#active?' do
    it 'returns true if status is approved' do
      hotel = build(:hotel, status: 'approved')
      expect(hotel.active?).to be true
    end

    it 'returns true if status is live' do
      hotel = build(:hotel, status: 'live')
      expect(hotel.active?).to be true
    end

    it 'returns false if status is registered' do
      hotel = build(:hotel, status: 'registered')
      expect(hotel.active?).to be false
    end
  end

  describe 'payment setting resolution' do
    let(:account) { create(:account) }
    let(:hotel) { create(:hotel, account: account) }

    it 'falls back to account payment setting when hotel has none' do
      account_setting = create(:payment_setting, settable: account, gateway: 'razorpay', status: 'active')

      expect(hotel.effective_payment_setting('razorpay')).to eq(account_setting)
    end

    it 'falls back to credential setting when neither hotel nor account has gateway setting' do
      credential_setting = Payments::CredentialSetting::Setting.new(
        gateway: 'razorpay',
        api_key: 'rzp_key',
        secret_key: 'rzp_secret',
        webhook_secret: 'whsec',
        status: 'active'
      )
      allow(Payments::CredentialSetting).to receive(:for_gateway).with('razorpay').and_return(credential_setting)

      expect(hotel.effective_payment_setting('razorpay')).to eq(credential_setting)
    end

    it 'uses credential default as checkout gateway when db settings are missing' do
      credential_setting = Payments::CredentialSetting::Setting.new(
        gateway: 'razorpay',
        api_key: 'rzp_key',
        secret_key: 'rzp_secret',
        webhook_secret: 'whsec',
        status: 'active'
      )
      allow(Payments::CredentialSetting).to receive(:default).and_return(credential_setting)

      expect(hotel.checkout_payment_gateway).to eq('razorpay')
    end
  end
end
