require 'rails_helper'

RSpec.describe BookingAuditLog, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:hotel) }
    it { is_expected.to belong_to(:auditable) }
    it { is_expected.to belong_to(:user).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:action_type) }
  end

  describe '#display_auditable_name' do
    it 'returns formatted name for Booking' do
      booking = create(:booking)
      log = create(:booking_audit_log, auditable: booking)
      expect(log.display_auditable_name).to eq("Booking")
    end

    it 'returns formatted name for BookingQuote' do
      quote = create(:booking_quote)
      log = create(:booking_audit_log, auditable: quote)
      expect(log.display_auditable_name).to eq("Quote")
    end

    it 'returns formatted name for BookingRoom' do
      room = create(:booking_room)
      log = create(:booking_audit_log, auditable: room)
      expect(log.display_auditable_name).to eq("Room Assignment")
    end
  end

  describe '#display_value_change' do
    it 'formats changes correctly' do
      log = build(:booking_audit_log,
        old_value: { 'status' => 'pending', 'guest_name' => 'Old Name' },
        new_value: { 'status' => 'confirmed', 'guest_name' => 'New Name' }
      )

      display = log.display_value_change
      expect(display).to include("Status: pending -> confirmed")
      expect(display).to include("Guest Name: Old Name -> New Name")
    end

    it 'handles nil values' do
      log = build(:booking_audit_log,
        old_value: { 'notes' => nil },
        new_value: { 'notes' => 'Some notes' }
      )

      expect(log.display_value_change).to eq("Notes: N/A -> Some notes")
    end
  end
end
