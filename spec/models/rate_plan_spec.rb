require 'rails_helper'

RSpec.describe RatePlan, type: :model do
  describe 'associations' do
    it { should belong_to(:hotel) }
    it { should have_many(:room_type_rate_plans).dependent(:destroy) }
    it { should have_many(:room_types).through(:room_type_rate_plans) }
    it { should have_many(:room_rates).dependent(:destroy) }
    it { should have_many(:rate_plan_age_bands).dependent(:destroy) }
    it { should have_one(:channel_mapping).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:sell_mode) }
    it { should validate_inclusion_of(:sell_mode).in_array(%w[per_room per_person]) }
    it { should validate_presence_of(:currency) }
  end

  describe 'custom validations' do
    let(:hotel) { create(:hotel, allow_pax_pricing: false) }
    let(:rate_plan) { build(:rate_plan, hotel: hotel, sell_mode: 'per_person') }

    context 'when allow_pax_pricing is false' do
      it 'does not allow sell_mode to be per_person' do
        expect(rate_plan).not_to be_valid
        expect(rate_plan.errors[:sell_mode]).to include("cannot be set to Per Person unless allowed by admin")
      end

      it 'allows sell_mode to be per_room' do
        rate_plan.sell_mode = 'per_room'
        expect(rate_plan).to be_valid
      end
    end

    context 'when allow_pax_pricing is true' do
      before do
        hotel.update!(allow_pax_pricing: true)
      end

      it 'allows sell_mode to be per_person' do
        expect(rate_plan).to be_valid
      end
    end
  end

  describe '#sell_mode_matches_hotel_exclusivity' do
    let(:hotel) { create(:hotel, allow_pax_pricing: true, pax_pricing_only: true) }

    context 'when the hotel is pax_pricing_only' do
      it 'rejects a per_room rate plan that is not a special tier or the standard rate' do
        rate_plan = build(:rate_plan, hotel: hotel, name: 'Bed & Breakfast', sell_mode: 'per_room')

        expect(rate_plan).not_to be_valid
        expect(rate_plan.errors[:sell_mode]).to include('must be Per Person while this hotel is set to pax-pricing only')
      end

      it 'allows a per_person rate plan' do
        rate_plan = build(:rate_plan, hotel: hotel, name: 'Bed & Breakfast', sell_mode: 'per_person')

        expect(rate_plan).to be_valid
      end

      it 'exempts the system "Standard Rate" plan even in per_room mode' do
        rate_plan = build(:rate_plan, hotel: hotel, name: 'Standard Rate', sell_mode: 'per_room')

        expect(rate_plan).to be_valid
      end

      it 'exempts special-tier plans like Walk-in Rate even in per_room mode' do
        rate_plan = build(:rate_plan, hotel: hotel, name: 'Walk-in Rate', sell_mode: 'per_room')

        expect(rate_plan).to be_valid
      end
    end

    context 'when the hotel is not pax_pricing_only' do
      it 'allows a per_room rate plan' do
        hotel.update!(pax_pricing_only: false)
        rate_plan = build(:rate_plan, hotel: hotel, name: 'Bed & Breakfast', sell_mode: 'per_room')

        expect(rate_plan).to be_valid
      end
    end
  end

  describe '#age_banded?' do
    let(:hotel) { create(:hotel, allow_pax_pricing: true) }

    it 'is false for a per_room rate plan even with bands present' do
      rate_plan = create(:rate_plan, hotel: hotel, sell_mode: 'per_room')
      create(:rate_plan_age_band, rate_plan: rate_plan)

      expect(rate_plan.age_banded?).to be false
    end

    it 'is false for a per_person rate plan with no bands configured' do
      rate_plan = create(:rate_plan, hotel: hotel, sell_mode: 'per_person')

      expect(rate_plan.age_banded?).to be false
    end

    it 'is true for a per_person rate plan with bands configured' do
      rate_plan = create(:rate_plan, hotel: hotel, sell_mode: 'per_person')
      create(:rate_plan_age_band, rate_plan: rate_plan)

      expect(rate_plan.age_banded?).to be true
    end
  end

  describe '#band_for_age' do
    let(:hotel) { create(:hotel, allow_pax_pricing: true) }
    let(:rate_plan) { create(:rate_plan, :age_banded, hotel: hotel) }

    it 'resolves the band covering the given age' do
      expect(rate_plan.band_for_age(6).label).to eq('Child')
      expect(rate_plan.band_for_age(15).label).to eq('Teen')
    end

    it 'returns nil for an age not covered by any band' do
      expect(rate_plan.band_for_age(30)).to be_nil
    end
  end

  describe '#sync_with_channel_manager' do
    let(:hotel) { create(:hotel, allow_pax_pricing: true, preferred_channel_manager: 'channex') }

    it 'does not enqueue a sync job for a per_person rate plan' do
      expect {
        create(:rate_plan, hotel: hotel, sell_mode: 'per_person')
      }.not_to have_enqueued_job(ChannelManagers::SyncStructureJob)
    end

    it 'enqueues a sync job for a per_room rate plan' do
      expect {
        create(:rate_plan, hotel: hotel, sell_mode: 'per_room')
      }.to have_enqueued_job(ChannelManagers::SyncStructureJob)
    end
  end
end
