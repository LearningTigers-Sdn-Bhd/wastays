require 'rails_helper'

RSpec.describe RatePlan, type: :model do
  describe 'associations' do
    it { should belong_to(:hotel) }
    it { should have_many(:room_type_rate_plans).dependent(:destroy) }
    it { should have_many(:room_types).through(:room_type_rate_plans) }
    it { should have_many(:room_rates).dependent(:destroy) }
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
end
