require 'rails_helper'

RSpec.describe ChannelManagers::FullRefreshService do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:service) { described_class.new(hotel: hotel) }

  describe '#call' do
    it 'triggers ARI sync for a long window' do
      expect(ChannelManagers::SyncJob).to receive(:perform_later).with(
        hotel.id,
        anything,
        anything,
        sync_availability: true,
        sync_rates: true,
        sync_restrictions: true,
        room_type_ids: nil,
        rate_plan_ids: nil
      )
      service.call
    end

    it 'does not publish channel data while the property is in training' do
      hotel.update!(status: "pending_review", training_started_at: Time.current)

      expect(ChannelManagers::SyncJob).not_to receive(:perform_later)
      result = service.call

      expect(result).not_to be_success
      expect(result.message).to eq("Channel publishing is unavailable while this property is in training.")
    end
  end
end
