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

    it "accepts an optional PNG, JPEG, or WebP hotel icon up to 2 MB" do
      Hotel::ICON_CONTENT_TYPES.each do |content_type|
        extension = content_type.split("/").last.sub("jpeg", "jpg")
        hotel = create(:hotel)
        hotel.icon.attach(
          io: StringIO.new("image-content"),
          filename: "icon.#{extension}",
          content_type: content_type
        )

        expect(hotel).to be_valid
      end

      expect(create(:hotel)).to be_valid
    end

    it "rejects SVG, non-image, and oversized hotel icons" do
      [ [ "icon.svg", "image/svg+xml", "<svg></svg>" ],
        [ "notes.txt", "text/plain", "not an image" ],
        [ "large.png", "image/png", "x" * (Hotel::ICON_MAX_SIZE + 1) ] ].each do |filename, content_type, content|
        hotel = build(:hotel)
        hotel.icon.attach(io: StringIO.new(content), filename: filename, content_type: content_type)

        expect(hotel).not_to be_valid
        expect(hotel.errors[:icon]).to be_present
      end
    end

    it "keeps one attachment when the hotel icon is replaced" do
      hotel = create(:hotel)
      hotel.icon.attach(io: StringIO.new("first"), filename: "first.png", content_type: "image/png")
      hotel.icon.attach(io: StringIO.new("second"), filename: "second.webp", content_type: "image/webp")

      expect(hotel.reload.icon.filename.to_s).to eq("second.webp")
      expect(ActiveStorage::Attachment.where(record: hotel, name: "icon").count).to eq(1)
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
      expect(Hotel::STATUSES).to match_array(%w[setup pending_review ready_to_launch live suspended])
    end
  end

  describe 'lifecycle status' do
    it 'rejects a status outside the canonical lifecycle' do
      hotel = build(:hotel, status: 'approved')

      expect(hotel).not_to be_valid
      expect(hotel.errors[:status]).to be_present
    end

    it 'accepts every canonical status' do
      Hotel::STATUSES.each do |status|
        hotel = build(:hotel, status: status)
        hotel.valid?

        expect(hotel.errors[:status]).to be_empty, "expected #{status} to be a valid hotel status"
      end
    end


    it "accepts only canonical training decisions and reset states" do
      hotel = create(:hotel)
      hotel.assign_attributes(training_data_decision: "discard", training_reset_state: "done")

      expect(hotel).not_to be_valid
      expect(hotel.errors[:training_data_decision]).to be_present
      expect(hotel.errors[:training_reset_state]).to be_present

      hotel.training_data_decision = "keep"
      hotel.training_reset_state = "processing"

      expect(hotel).to be_valid
    end
  end

  describe '#active?' do
    it 'returns true if status is live' do
      hotel = build(:hotel, status: 'live')
      expect(hotel.active?).to be true
    end

    it 'returns false while the hotel is still in setup' do
      hotel = build(:hotel, status: 'setup')
      expect(hotel.active?).to be false
    end

    it 'returns false while the hotel is awaiting review' do
      hotel = build(:hotel, status: 'pending_review')
      expect(hotel.active?).to be false
    end
  end

  describe "#training_mode?" do
    it "is true only during a started pending-review or launch-decision session" do
      started_at = Time.current

      expect(build(:hotel, status: "pending_review", training_started_at: started_at)).to be_training_mode
      expect(build(:hotel, status: "ready_to_launch", training_started_at: started_at)).to be_training_mode
      expect(build(:hotel, status: "pending_review", training_started_at: nil)).not_to be_training_mode
      expect(build(:hotel, status: "live", training_started_at: started_at)).not_to be_training_mode
    end
  end

  describe "#training_reset_in_progress?" do
    it "covers queued and processing reset work" do
      expect(build(:hotel, training_reset_state: "queued")).to be_training_reset_in_progress
      expect(build(:hotel, training_reset_state: "processing")).to be_training_reset_in_progress
      expect(build(:hotel, training_reset_state: "failed")).not_to be_training_reset_in_progress
      expect(build(:hotel, training_reset_state: nil)).not_to be_training_reset_in_progress
    end
  end

  describe '#onboarding?' do
    it 'is true only in setup' do
      expect(build(:hotel, status: 'setup')).to be_onboarding
      expect(build(:hotel, status: 'pending_review')).not_to be_onboarding
      expect(build(:hotel, status: 'live')).not_to be_onboarding
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

  describe '#inventory_ready?' do
    let(:hotel) { create(:hotel) }
    let!(:room) { create(:room_type, hotel: hotel, quantity: 2, base_price: 110, max_adults: 2) }

    it 'refuses a hotel priced for the next month but empty for the rest of the year' do
      (Date.current..Date.current + 30.days).each do |date|
        create(:room_inventory, room_type: room, date: date, quantity: 2, status: 'open')
      end

      expect(hotel.inventory_ready?).to be false
    end

    it 'accepts a hotel stocked and priced across the full horizon' do
      (Date.current..Date.current + 364.days).each do |date|
        create(:room_inventory, room_type: room, date: date, quantity: 2, status: 'open')
      end

      expect(hotel.inventory_ready?).to be true
    end
  end

  describe 'unique_id' do
    it 'assigns a numeric code on create' do
      hotel = create(:hotel)

      expect(hotel.unique_id).to match(/\A\d+\z/)
      expect(hotel.unique_id.to_i).to be >= Hotel::UNIQUE_ID_FLOOR
    end

    it 'starts at the floor when no hotel has been issued a code' do
      expect(create(:hotel).unique_id).to eq('10101')
    end

    it 'issues the next number to the hotel created after it' do
      first = create(:hotel)
      second = create(:hotel)

      expect(second.unique_id.to_i).to eq(first.unique_id.to_i + 1)
    end

    it 'counts from the highest code already issued, not the row count' do
      create(:hotel, unique_id: '20500')

      expect(create(:hotel).unique_id).to eq('20501')
    end

    it 'is the URL parameter' do
      hotel = create(:hotel)

      expect(hotel.to_param).to eq(hotel.unique_id)
    end

    it 'cannot be changed once the hotel exists' do
      hotel = create(:hotel)
      hotel.unique_id = '99999'

      expect(hotel).not_to be_valid
      expect(hotel.errors[:unique_id]).to include('cannot be changed after the hotel is created')
    end

    it 'rejects a code already taken by another hotel' do
      taken = create(:hotel).unique_id

      expect(build(:hotel, unique_id: taken)).not_to be_valid
    end
  end

  describe 'slug' do
    it 'survives a rename so links issued before it keep resolving' do
      hotel = create(:hotel)
      original = hotel.slug

      hotel.update!(name: 'Completely Different Name')

      expect(hotel.reload.slug).to eq(original)
    end
  end

  describe '.locate' do
    let!(:hotel) { create(:hotel) }

    it 'finds by unique_id regardless of case' do
      expect(Hotel.locate(hotel.unique_id)).to eq(hotel)
      expect(Hotel.locate(hotel.unique_id.downcase)).to eq(hotel)
    end

    it 'still finds by the legacy slug' do
      expect(Hotel.locate(hotel.slug)).to eq(hotel)
    end

    # A hotel is addressed by the code it was issued, never by its row id — even now
    # that both are numbers.
    it 'refuses a row id' do
      expect(Hotel.locate(hotel.id.to_s)).to be_nil
    end

    it 'returns nil for a blank or unknown key' do
      expect(Hotel.locate(nil)).to be_nil
      expect(Hotel.locate('')).to be_nil
      expect(Hotel.locate('90909')).to be_nil
    end

    it 'honours the given scope' do
      other = create(:hotel)

      expect(Hotel.locate(hotel.unique_id, scope: Hotel.where(id: other.id))).to be_nil
    end

    it 'raises from locate! when nothing matches' do
      expect { Hotel.locate!('90909') }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
