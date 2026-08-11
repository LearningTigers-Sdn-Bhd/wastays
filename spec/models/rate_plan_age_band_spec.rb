require 'rails_helper'

RSpec.describe RatePlanAgeBand, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:rate_plan) }
  end

  describe 'validations' do
    subject(:band) { build(:rate_plan_age_band) }

    it { is_expected.to validate_presence_of(:min_age) }
    it { is_expected.to validate_presence_of(:max_age) }
    it { is_expected.to validate_numericality_of(:min_age).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:max_age).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:price_value).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_inclusion_of(:pricing_mode).in_array(%w[multiplier amount]) }

    it 'rejects a max_age below min_age' do
      band.min_age = 10
      band.max_age = 5

      expect(band).not_to be_valid
      expect(band.errors[:max_age]).to be_present
    end

    it 'rejects a band that overlaps an existing sibling band on the same rate plan' do
      hotel = create(:hotel, :per_person)
      rate_plan = create(:rate_plan, hotel: hotel)
      create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 4, max_age: 11)
      overlapping = build(:rate_plan_age_band, rate_plan: rate_plan, min_age: 10, max_age: 15)

      expect(overlapping).not_to be_valid
      expect(overlapping.errors[:base]).to be_present
    end

    it 'allows adjacent, non-overlapping bands with a gap between them' do
      hotel = create(:hotel, :per_person)
      rate_plan = create(:rate_plan, hotel: hotel)
      create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 4, max_age: 11)
      gap_band = build(:rate_plan_age_band, rate_plan: rate_plan, min_age: 13, max_age: 17)

      expect(gap_band).to be_valid
    end
  end

  describe '#price_for' do
    it 'takes price_value as a whole percent of the anchor price for multiplier mode' do
      band = build(:rate_plan_age_band, pricing_mode: 'multiplier', price_value: 40)
      expect(band.price_for(100.to_d)).to eq(40.to_d)
    end

    it 'ignores the anchor price and returns the flat value for amount mode' do
      band = build(:rate_plan_age_band, :amount, price_value: 30.0)
      expect(band.price_for(999.to_d)).to eq(30.0.to_d)
    end
  end

  describe 'default_scope' do
    it 'orders bands by position then min_age' do
      hotel = create(:hotel, :per_person)
      rate_plan = create(:rate_plan, hotel: hotel)
      second = create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 12, max_age: 17, position: 1)
      first = create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 4, max_age: 11, position: 0)

      expect(rate_plan.rate_plan_age_bands.to_a).to eq([ first, second ])
    end
  end
end
