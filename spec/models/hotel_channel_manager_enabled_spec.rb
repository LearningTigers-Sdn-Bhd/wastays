# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hotel, "#channel_manager_enabled?" do
  it "is true only for a provider we have an adapter for" do
    expect(build(:hotel, preferred_channel_manager: "channex").channel_manager_enabled?).to be(true)
  end

  [ "undecided", "none", "unsupported", "", nil ].each do |value|
    it "is false for #{value.inspect}" do
      expect(build(:hotel, preferred_channel_manager: value).channel_manager_enabled?).to be(false)
    end
  end

  describe "hotels that are not connected to a channel manager" do
    include ActiveJob::TestHelper

    %w[undecided none].each do |value|
      context "when preferred_channel_manager is #{value}" do
        let(:hotel) { create(:hotel, preferred_channel_manager: value) }
        let(:room_type) { create(:room_type, hotel: hotel) }

        it "does not enqueue ARI sync when inventory changes" do
          expect { create(:room_inventory, room_type: room_type, date: Date.current + 3) }
            .not_to have_enqueued_job(ChannelManagers::BufferAriSyncJob)
        end

        it "makes the sync jobs a no-op instead of raising" do
          expect { ChannelManagers::SyncJob.perform_now(hotel.id, Date.current.to_s, (Date.current + 3).to_s) }.not_to raise_error
          expect { ChannelManagers::BufferAriSyncJob.perform_now(hotel.id, Date.current.to_s, type: :availability) }.not_to raise_error
          expect { ChannelManagers::FlushAriSyncJob.perform_now(hotel.id) }.not_to raise_error
          expect { ChannelManagers::SyncStructureJob.perform_now("RoomType", room_type.id, "sync") }.not_to raise_error
        end
      end
    end

    it "still enqueues ARI sync for a Channex hotel" do
      hotel = create(:hotel, preferred_channel_manager: "channex")
      room_type = create(:room_type, hotel: hotel)

      expect { create(:room_inventory, room_type: room_type, date: Date.current + 3) }
        .to have_enqueued_job(ChannelManagers::BufferAriSyncJob)
    end
  end
end
