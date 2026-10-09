require 'rails_helper'

RSpec.describe ChannelManagers::FullRefreshService do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:service) { described_class.new(hotel: hotel) }

  describe '#call' do
    it 'triggers ARI sync for a long window' do
      expect { service.call }.to have_enqueued_job(ChannelManagers::SyncJob).with(
        hotel.id,
        anything,
        anything,
        sync_availability: true,
        sync_rates: true,
        sync_restrictions: true,
        room_type_ids: nil,
        rate_plan_ids: nil
      )
    end

    it "opens the window on the hotel's today, not UTC's, at the 2 am refresh",
       frozen_time: Time.find_zone("Asia/Kuala_Lumpur").local(2026, 11, 10, 2, 0) do
      hotel.update!(time_zone: "Asia/Kuala_Lumpur")

      expect { service.call }.to have_enqueued_job(ChannelManagers::SyncJob)
        .with(hotel.id, Date.new(2026, 11, 10), Date.new(2026, 11, 10) + 499.days, hash_including(sync_availability: true))
    end

    it 'does not publish channel data while the property is in training' do
      hotel.update!(status: "pending_review", training_started_at: Time.current)

      result = nil
      expect { result = service.call }.not_to have_enqueued_job(ChannelManagers::SyncJob)

      expect(result).not_to be_success
      expect(result.message).to eq("Channel publishing is unavailable while this property is in training.")
    end
  end
end
