require 'rails_helper'

RSpec.describe HotelOps::BulkUpdateRates do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:start_date) { Date.today }
  let(:end_date) { Date.today + 6.days }
  let(:price) { 150.0 }
  let(:currency) { 'MYR' }

  subject do
    described_class.new(
      hotel: hotel,
      room_type: room_type,
      start_date: start_date,
      end_date: end_date,
      price: price,
      currency: currency,
      user: user
    )
  end

  describe '#call' do
    it 'creates room rates for the specified range' do
      expect {
        result = subject.call
        expect(result[:success]).to be true
      }.to change(RoomRate, :count).by(7)
    end

    it 'sets the correct price and currency' do
      subject.call
      rate = room_type.room_rates.find_by(date: start_date)
      expect(rate.price).to eq(price)
      expect(rate.currency).to eq(currency)
    end

    it 'updates existing room rates if they exist' do
      create(:room_rate, room_type: room_type, date: start_date, price: 100.0)

      expect {
        result = subject.call
        expect(result[:success]).to be true
      }.to change(RoomRate, :count).by(6) # 7 total, but 1 already exists

      expect(room_type.room_rates.find_by(date: start_date).price).to eq(price)
    end

    it 'creates audit logs for changes' do
      expect {
        subject.call
      }.to change(InventoryAuditLog, :count).by(7)

      audit_log = InventoryAuditLog.last
      expect(audit_log.action_type).to eq('rate_update')
      expect(audit_log.room_type).to eq(room_type)
      expect(audit_log.user).to eq(user)
    end

    it 'does not create audit log if price remains the same' do
      create(:room_rate, room_type: room_type, date: start_date, price: price)

      expect {
        subject.call
      }.to change(InventoryAuditLog, :count).by(6) # 7 total, but 1 has same price
    end

    context 'when an error occurs' do
      before do
        allow_any_instance_of(RoomRate).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
      end

      it 'returns success false and an error message' do
        result = subject.call
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end

      it 'rolls back the transaction' do
        expect {
          subject.call
        }.not_to change(RoomRate, :count)
      end
    end
  end
end
