require 'rails_helper'

RSpec.describe RoomInventory, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:room_type) }
  end

  describe 'validations' do
    subject(:room_inventory) { create(:room_inventory) }

    it { is_expected.to validate_presence_of(:date) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[open closed]) }
    it { is_expected.to validate_uniqueness_of(:date).scoped_to(:room_type_id) }
  end

  describe 'scopes' do
    let!(:open_inventory) { create(:room_inventory, status: 'open') }
    let!(:closed_inventory) { create(:room_inventory, status: 'closed') }

    it 'filters open inventory' do
      expect(described_class.open).to contain_exactly(open_inventory)
    end

    it 'filters closed inventory' do
      expect(described_class.closed).to contain_exactly(closed_inventory)
    end
  end
end
