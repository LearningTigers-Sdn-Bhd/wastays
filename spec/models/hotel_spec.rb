require 'rails_helper'

RSpec.describe Hotel, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_many(:user_hotel_accesses).dependent(:destroy) }
    it { should have_many(:users).through(:user_hotel_accesses) }
    it { should have_many(:room_groups).dependent(:destroy) }
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

  describe "prefix history" do
    it "keeps issued document references stable when the hotel prefix changes" do
      hotel = create(:hotel, hotel_prefix: "OLD")
      booking = create(:booking, hotel: hotel)
      original_reference = booking.formatted_reservation_number

      hotel.update!(hotel_prefix: "NEW")

      expect(booking.reload.formatted_reservation_number).to eq(original_reference)
      expect(hotel.hotel_prefix_histories.pluck(:prefix)).to contain_exactly("OLD", "NEW")
    end

    it "does not allow another hotel to reuse a retired prefix" do
      hotel = create(:hotel, hotel_prefix: "OLD")
      hotel.update!(hotel_prefix: "NEW")

      other = build(:hotel, hotel_prefix: "OLD")

      expect(other).not_to be_valid
      expect(other.errors[:hotel_prefix]).to include("has already been used by another hotel")
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

      form = HotelPortal::TaxSettingsForm.new(hotel, ActionController::Parameters.new(hotel: { sst_enabled: false, tourism_tax_enabled: false }))
      form.save

      expect(hotel.transaction_codes.find_by!(system_key: 'sst_tax')).not_to be_active
      expect(hotel.transaction_codes.find_by!(system_key: 'tourism_tax')).not_to be_active

      form = HotelPortal::TaxSettingsForm.new(hotel, ActionController::Parameters.new(hotel: { sst_enabled: true, tourism_tax_enabled: true }))
      form.save

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

  describe 'google map link parsing' do
    it 'returns nil when google_map_link is blank' do
      hotel = build(:hotel, google_map_link: nil)
      expect(hotel.latitude).to be_nil
      expect(hotel.longitude).to be_nil
    end

    it 'extracts coordinates from standard web url with !3d/!4d parameters' do
      hotel = build(:hotel, google_map_link: 'https://www.google.com/maps/place/Sample+Hotel/@5.9771228,116.0622732,15z/data=!4m6!3m5!1s0x323b699a6cf71ecf:0x5e95df94691456a0!8m2!3d5.9771228!4d116.0622732!16s%2Fg%2F11b6zg5y5s?entry=ttu')
      expect(hotel.latitude).to eq(5.9771228)
      expect(hotel.longitude).to eq(116.0622732)
    end

    it 'extracts coordinates from fallback @url format' do
      hotel = build(:hotel, google_map_link: 'https://www.google.com/maps/place/Sample+Hotel/@5.9771228,116.0622732,15z')
      expect(hotel.latitude).to eq(5.9771228)
      expect(hotel.longitude).to eq(116.0622732)
    end
  end

  describe 'sell mode' do
    let(:hotel) { create(:hotel) }

    it 'requires an explicit value on creation' do
      account = create(:account)

      expect(build(:hotel, account: account, sell_mode: nil)).not_to be_valid
      expect(build(:hotel, account: account, sell_mode: 'per_room')).to be_valid
      expect(build(:hotel, account: account, sell_mode: 'per_person')).to be_valid
    end

    it 'rejects a value outside the rate plan vocabulary' do
      hotel.sell_mode = 'per_night'
      expect(hotel).not_to be_valid
      expect(hotel.errors[:sell_mode]).to be_present
    end

    describe '#sells_per_person?' do
      it 'is true only for per_person' do
        expect(hotel.sells_per_person?).to be false
        expect(create(:hotel, :per_person).sells_per_person?).to be true
      end
    end

    describe 'locking after creation' do
      it 'refuses a per-room to per-guest change before the hotel is bookable' do
        expect(hotel.update(sell_mode: 'per_person')).to be false
        expect(hotel.errors[:sell_mode]).to include('cannot be changed after the hotel is created')
        expect(hotel.reload.sell_mode).to eq('per_room')
      end

      it 'refuses a per-guest to per-room change' do
        hotel = create(:hotel, :per_person)

        expect(hotel.update(sell_mode: 'per_room')).to be false
        expect(hotel.reload.sell_mode).to eq('per_person')
      end

      it 'leaves the hotel’s other attributes editable while locked' do
        expect(hotel.update(name: "#{hotel.name} Resort")).to be true
      end
    end
  end
end
