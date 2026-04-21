require 'rails_helper'

RSpec.describe InventoryAuditLog, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:hotel) }
    it { is_expected.to belong_to(:room_type).optional }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:action_type) }
  end

  describe '#display_details' do
    it 'returns room type name when present' do
      room_type = create(:room_type, name: 'Deluxe Room')
      log = create(:inventory_audit_log, room_type: room_type)

      expect(log.display_details).to eq('Deluxe Room')
    end

    it 'returns property-wide label when room type is missing' do
      log = create(:inventory_audit_log, room_type: nil)

      expect(log.display_details).to eq('Property-wide')
    end
  end

  describe '#display_value_change' do
    it 'formats rate changes with date and currency' do
      log = build(
        :inventory_audit_log,
        action_type: 'rate_update',
        old_value: { 'date' => '2026-04-21', 'currency' => 'MYR', 'price' => 100.0 },
        new_value: { 'date' => '2026-04-21', 'currency' => 'MYR', 'price' => 120.0 }
      )

      expect(log.display_value_change).to eq('2026-04-21: MYR 100.0 -> MYR 120.0')
    end

    it 'formats inventory changes with quantity and status' do
      log = build(
        :inventory_audit_log,
        action_type: 'inventory_update',
        old_value: { 'date' => '2026-04-21', 'quantity' => 5, 'status' => 'open' },
        new_value: { 'date' => '2026-04-21', 'quantity' => 2, 'status' => 'closed' }
      )

      expect(log.display_value_change).to eq('2026-04-21: Qty 5 / Open -> Qty 2 / Closed')
    end
  end
end
