require 'rails_helper'

RSpec.describe RoomType, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:hotel) }
    it { is_expected.to have_many(:room_rates).dependent(:destroy) }
    it { is_expected.to have_many(:room_inventories).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:max_adults) }
    it { is_expected.to validate_numericality_of(:max_adults).is_greater_than(0) }
    it { is_expected.to validate_presence_of(:base_price) }
    it { is_expected.to validate_numericality_of(:base_price).is_greater_than_or_equal_to(0) }
  end

  describe 'scopes' do
    describe '.unassigned' do
      let!(:hotel) { create(:hotel) }
      let!(:grouped_room_type) { create(:room_type, hotel: hotel, room_group: create(:room_group, hotel: hotel)) }
      let!(:ungrouped_room_type) { create(:room_type, hotel: hotel, room_group: nil) }

      it 'returns only unassigned room types' do
        expect(described_class.unassigned).to include(ungrouped_room_type)
        expect(described_class.unassigned).not_to include(grouped_room_type)
      end
    end
  end
end
