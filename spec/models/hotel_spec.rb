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
    it { should validate_presence_of(:business_starts_at) }
    it { should validate_presence_of(:business_ends_at) }

    it 'requires a non-negative arrival grace period in seconds' do
      hotel = build(:hotel, arrival_grace_period: -1)

      expect(hotel).not_to be_valid
      expect(hotel.errors[:arrival_grace_period]).to be_present
    end
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

  describe 'primary tax transaction codes' do
    it 'creates SST and tourism tax codes using the hotel tax enabled settings' do
      hotel = create(:hotel, sst_enabled: false, tourism_tax_enabled: false)

      expect(hotel.transaction_codes.find_by!(system_key: 'sst_tax')).not_to be_active
      expect(hotel.transaction_codes.find_by!(system_key: 'tourism_tax')).not_to be_active
    end

    it 'syncs SST and tourism tax code active state when settings change' do
      hotel = create(:hotel, sst_enabled: true, tourism_tax_enabled: true)

      hotel.update!(sst_enabled: false, tourism_tax_enabled: false)

      expect(hotel.transaction_codes.find_by!(system_key: 'sst_tax')).not_to be_active
      expect(hotel.transaction_codes.find_by!(system_key: 'tourism_tax')).not_to be_active

      hotel.update!(sst_enabled: true, tourism_tax_enabled: true)

      expect(hotel.transaction_codes.find_by!(system_key: 'sst_tax')).to be_active
      expect(hotel.transaction_codes.find_by!(system_key: 'tourism_tax')).to be_active
    end
  end

  describe 'business dates' do
    let(:hotel) do
      build(:hotel,
        time_zone: 'Kuala Lumpur',
        business_starts_at: '08:00',
        business_ends_at: '02:00',
        arrival_grace_period: 7200)
    end
    let(:zone) { Time.find_zone('Kuala Lumpur') }

    it 'maps after-midnight time before business end to the previous business date' do
      expect(hotel.business_date_for(zone.local(2026, 5, 19, 1, 30))).to eq(Date.new(2026, 5, 18))
    end

    it 'uses the current calendar date at business end' do
      expect(hotel.business_date_for(zone.local(2026, 5, 19, 2, 0))).to eq(Date.new(2026, 5, 19))
    end

    it 'makes yesterday closable 30 minutes after business ends' do
      expect(hotel.latest_closable_business_date(zone.local(2026, 5, 19, 1, 59))).to eq(Date.new(2026, 5, 17))
      expect(hotel.latest_closable_business_date(zone.local(2026, 5, 19, 2, 0))).to eq(Date.new(2026, 5, 17))
      expect(hotel.latest_closable_business_date(zone.local(2026, 5, 19, 2, 29))).to eq(Date.new(2026, 5, 17))
      expect(hotel.latest_closable_business_date(zone.local(2026, 5, 19, 2, 30))).to eq(Date.new(2026, 5, 18))
      expect(hotel.latest_closable_business_date(zone.local(2026, 5, 19, 15, 0))).to eq(Date.new(2026, 5, 18))
    end

    it 'builds the business day window across midnight' do
      window = hotel.business_day_window_for(Date.new(2026, 5, 18))

      expect(window.begin).to eq(zone.local(2026, 5, 18, 8, 0))
      expect(window.end).to eq(zone.local(2026, 5, 19, 2, 0))
    end

    it 'uses the HotelBusinessDate row as accounting authority instead of the clock' do
      persisted_hotel = create(:hotel)
      record = persisted_hotel.current_business_date_record

      allow(persisted_hotel).to receive(:business_date_for).and_return(record.business_date + 5.days)

      expect(persisted_hotel.current_business_date_record).to eq(record)
      expect(persisted_hotel.current_business_date).to eq(record.business_date)
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
