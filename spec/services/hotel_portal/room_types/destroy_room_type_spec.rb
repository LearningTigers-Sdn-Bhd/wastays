# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::RoomTypes::DestroyRoomType do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let!(:room_type) { create(:room_type, hotel: hotel) }

  describe "#call" do
    context "when the room type has no channel mapping" do
      it "destroys the room type successfully" do
        result = described_class.new(room_type: room_type).call

        expect(result.success?).to be true
        expect(RoomType.exists?(room_type.id)).to be false
      end

      it "does not enqueue a channel manager sync job" do
        expect(ChannelManagers::SyncStructureJob).not_to receive(:perform_later)

        described_class.new(room_type: room_type).call
      end
    end

    context "when the room type is synced with a channel manager" do
      before do
        room_type.create_channel_mapping!(external_id: "rt_123", provider: "channex")
      end

      it "destroys the room type and enqueues a delete sync job" do
        expect(ChannelManagers::SyncStructureJob).to receive(:perform_later).with(
          "RoomType",
          nil,
          "delete",
          hotel_id: hotel.id,
          external_id: "rt_123"
        )

        result = described_class.new(room_type: room_type).call

        expect(result.success?).to be true
        expect(RoomType.exists?(room_type.id)).to be false
      end
    end

    context "when the room type has a pending channel mapping" do
      before do
        room_type.create_channel_mapping!(external_id: "pending", provider: "channex")
      end

      it "destroys the room type without enqueuing a sync job" do
        expect(ChannelManagers::SyncStructureJob).not_to receive(:perform_later)

        result = described_class.new(room_type: room_type).call

        expect(result.success?).to be true
      end
    end

    context "when the room type cannot be destroyed" do
      before do
        booking = create(:booking, hotel: hotel)
        create(:booking_room, booking: booking, room_type: room_type)
      end

      it "returns a failure result with errors" do
        result = described_class.new(room_type: room_type).call

        expect(result.success?).to be false
        expect(result.errors).to be_present
      end
    end
  end
end
