require 'rails_helper'

RSpec.describe GuestArrival::StartPreCheckin do
  describe '#call' do
    let(:booking) { create(:booking, pre_checkin_status: nil) }

    it 'creates pre-checkin and updates booking pre_checkin_status' do
      result = described_class.new(booking).call

      expect(result.success?).to be(true)
      expect(result.pre_checkin).to be_persisted
      expect(result.pre_checkin.status).to eq('pending')
      expect(result.pre_checkin.document_status).to eq('pending')
      expect(result.pre_checkin.signature_status).to eq('pending')
      expect(booking.reload.pre_checkin_status).to eq('pending')
    end

    it 'returns existing pre-checkin when already present' do
      existing = create(:pre_checkin, booking: booking)

      result = described_class.new(booking).call

      expect(result.success?).to be(true)
      expect(result.pre_checkin).to eq(existing)
      expect(booking.reload.pre_checkin).to eq(existing)
    end

    it 'returns failure result when creation raises an error' do
      allow(booking).to receive(:create_pre_checkin!).and_raise(StandardError, 'boom')

      result = described_class.new(booking).call

      expect(result.success?).to be(false)
      expect(result.message).to include('Failed to start pre-checkin: boom')
    end
  end
end
