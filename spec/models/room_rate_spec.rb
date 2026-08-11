require 'rails_helper'

RSpec.describe RoomRate, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:room_type) }
  end

  describe 'validations' do
    subject(:room_rate) { create(:room_rate) }

    it { is_expected.to validate_presence_of(:date) }
    it { is_expected.to validate_presence_of(:price) }
    it { is_expected.to validate_numericality_of(:price).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:currency) }
    it { is_expected.to validate_uniqueness_of(:date).scoped_to(:room_type_id, :rate_plan_id, :currency).case_insensitive }
  end


  it "rejects adult occupancy prices above the room category capacity" do
    rate = build(:room_rate, room_type: create(:room_type, max_adults: 2), occupancy_prices: { "3" => 500 })

    expect(rate).not_to be_valid
    expect(rate.errors[:occupancy_prices]).to include("contains an adult occupancy outside the room category capacity")
  end
end
