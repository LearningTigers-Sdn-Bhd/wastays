require 'rails_helper'

RSpec.describe HotelOps::BulkUpdateInventory, frozen_time: Time.zone.local(2026, 8, 15, 12) do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:start_date) { Date.today }
  let(:end_date) { Date.today + 6.days }
  let(:quantity) { 5 }
  let(:status) { 'open' }

  subject do
    described_class.new(
      hotel: hotel,
      room_type: room_type,
      start_date: start_date,
      end_date: end_date,
      quantity: quantity,
      status: status,
      user: user
    )
  end

  describe '#call' do
    it 'creates room inventories for the specified range' do
      expect {
        result = subject.call
        expect(result[:success]).to be true
      }.to change(RoomInventory, :count).by(7)
    end

    it 'sets the correct quantity and status' do
      subject.call
      inventory = room_type.room_inventories.find_by(date: start_date)
      expect(inventory.quantity).to eq(quantity)
      expect(inventory.status).to eq(status)
    end

    it 'updates existing inventories if they exist' do
      create(:room_inventory, room_type: room_type, date: start_date, quantity: 2, status: 'closed')

      expect {
        result = subject.call
        expect(result[:success]).to be true
      }.to change(RoomInventory, :count).by(6) # 7 total, but 1 already exists

      inventory = room_type.room_inventories.find_by(date: start_date)
      expect(inventory.quantity).to eq(quantity)
      expect(inventory.status).to eq(status)
    end

    it 'creates audit logs for changes' do
      expect {
        subject.call
      }.to change(InventoryAuditLog, :count).by(7)

      audit_log = InventoryAuditLog.last
      expect(audit_log.action_type).to eq('inventory_update')
      expect(audit_log.room_type).to eq(room_type)
      expect(audit_log.user).to eq(user)
    end

    it 'does not create audit log if quantity and status remain the same' do
      create(:room_inventory, room_type: room_type, date: start_date, quantity: quantity, status: status)

      expect {
        subject.call
      }.to change(InventoryAuditLog, :count).by(6) # 7 total, but 1 has same values
    end

    context 'when an error occurs' do
      before do
        allow_any_instance_of(RoomInventory).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
      end

      it 'returns success false and an error message' do
        result = subject.call
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end

      it 'rolls back the transaction' do
        expect {
          subject.call
        }.not_to change(RoomInventory, :count)
      end
    end

    context 'when only the status changes' do
      let(:room_type) { create(:room_type, hotel: hotel, quantity: 7) }

      def change_status(to)
        described_class.new(
          hotel: hotel, room_type: room_type, start_date: start_date, end_date: start_date,
          status: to, user: user
        ).call
      end

      it 'closes a date without resetting the rooms still free' do
        create(:room_inventory, room_type: room_type, date: start_date, quantity: 3, status: 'open')

        change_status('closed')

        inventory = room_type.room_inventories.find_by(date: start_date)
        expect(inventory).to have_attributes(status: 'closed', quantity: 3)
      end

      it 'reopens a date with the same free-room count it closed with' do
        create(:room_inventory, room_type: room_type, date: start_date, quantity: 3, status: 'closed')

        change_status('open')

        expect(room_type.room_inventories.find_by(date: start_date)).to have_attributes(status: 'open', quantity: 3)
      end

      it 'starts a new date from the rooms not already booked' do
        2.times { create(:booking_room, booking: create(:booking, hotel: hotel), room_type: room_type) }

        change_status('closed')

        expect(room_type.room_inventories.find_by(date: start_date).quantity).to eq(5)
      end
    end
  end
end
