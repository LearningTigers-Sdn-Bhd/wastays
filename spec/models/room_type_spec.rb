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

  describe '#standard_rate_plan' do
    let(:hotel) { create(:hotel) }
    let(:room_type) { create(:room_type, hotel: hotel) }

    it 'returns the plan created with the category' do
      expect(room_type.standard_rate_plan).to eq(room_type.rate_plans.sole)
    end

    it 'ignores a plan shared in from another category' do
      anchor = room_type.standard_rate_plan
      create(:rate_plan, :custom, hotel: hotel, name: "All Inclusive Package", room_type: room_type)

      expect(room_type.reload.standard_rate_plan).to eq(anchor)
    end

    it 'ignores special tiers regardless of their id order' do
      anchor = room_type.standard_rate_plan
      create(:rate_plan, :walk_in_tier, hotel: hotel, room_type: room_type)
      create(:rate_plan, :corporate_tier, hotel: hotel, room_type: room_type)

      expect(room_type.reload.standard_rate_plan).to eq(anchor)
    end

    it 'falls back to the oldest plan when no plan is marked standard' do
      room_type.rate_plans.sole.update!(kind: "custom", name: "Base Rate")
      renamed_anchor = room_type.reload.rate_plans.sole
      create(:rate_plan, :custom, hotel: hotel, name: "Later Plan", room_type: room_type)

      expect(room_type.reload.standard_rate_plan).to eq(renamed_anchor)
    end

    # AvailabilityService and the rates calendar both preload :rate_plans and
    # resolve the anchor per category, so a query here is a query per category.
    it 'does not query when rate_plans is already loaded' do
      room_type
      loaded = RoomType.includes(:rate_plans).find(room_type.id)

      queries = []
      subscriber = ->(_name, _start, _finish, _id, payload) do
        queries << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        loaded.standard_rate_plan
      end

      expect(queries).to be_empty
    end
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
