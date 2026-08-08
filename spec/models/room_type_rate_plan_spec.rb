require 'rails_helper'

RSpec.describe RoomTypeRatePlan, type: :model do
  describe 'validations' do
    it { should belong_to(:room_type) }
    it { should belong_to(:rate_plan) }
    it { should validate_inclusion_of(:pricing_mode).in_array(%w[fixed multiplier offset]) }

    it 'does not require pricing_value when pricing_mode is fixed' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'fixed', pricing_value: nil)
      expect(rtrp).to be_valid
    end

    it 'rejects a negative starting price when pricing_mode is fixed' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'fixed', pricing_value: -1)

      expect(rtrp).not_to be_valid
      expect(rtrp.errors[:pricing_value]).to be_present
    end

    it 'requires pricing_value when pricing_mode is multiplier' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'multiplier', pricing_value: nil)
      expect(rtrp).not_to be_valid
      expect(rtrp.errors[:pricing_value]).to be_present
    end

    it 'requires pricing_value when pricing_mode is offset' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'offset', pricing_value: nil)
      expect(rtrp).not_to be_valid
    end
  end

  describe '#derives_price?' do
    it 'is true for multiplier and offset' do
      expect(build(:room_type_rate_plan, pricing_mode: 'multiplier', pricing_value: 10).derives_price?).to be true
      expect(build(:room_type_rate_plan, pricing_mode: 'offset', pricing_value: 10).derives_price?).to be true
    end

    it 'is false for fixed' do
      expect(build(:room_type_rate_plan, pricing_mode: 'fixed').derives_price?).to be false
    end
  end

  describe '#derive_price' do
    it 'applies a positive multiplier as a markup' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'multiplier', pricing_value: 20)
      expect(rtrp.derive_price(100.to_d)).to eq(120.to_d)
    end

    it 'applies a negative multiplier as a discount' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'multiplier', pricing_value: -10)
      expect(rtrp.derive_price(100.to_d)).to eq(90.to_d)
    end

    it 'applies a positive offset as a flat markup' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'offset', pricing_value: 80)
      expect(rtrp.derive_price(100.to_d)).to eq(180.to_d)
    end

    it 'applies a negative offset as a flat discount' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'offset', pricing_value: -30)
      expect(rtrp.derive_price(100.to_d)).to eq(70.to_d)
    end

    it 'clamps a large negative offset to zero instead of going negative' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'offset', pricing_value: -1000)
      expect(rtrp.derive_price(100.to_d)).to eq(0.to_d)
    end

    it 'returns nil when the anchor price is nil' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'multiplier', pricing_value: 10)
      expect(rtrp.derive_price(nil)).to be_nil
    end

    it 'returns the anchor price unchanged for fixed mode' do
      rtrp = build(:room_type_rate_plan, pricing_mode: 'fixed', pricing_value: 999)
      expect(rtrp.derive_price(100.to_d)).to eq(100.to_d)
    end
  end
end
