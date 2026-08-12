# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::RoomTypes::SaveRoomType do
  let(:hotel) { create(:hotel) }
  let(:params) do
    {
      name: "Deluxe Room",
      base_price: 100,
      quantity: 2,
      max_adults: 2,
      room_numbers: [ "101", "102", "" ]
    }
  end

  describe "#call" do
    context "when creating a new room type" do
      subject { described_class.new(hotel: hotel, params: params) }

      it "creates the room type and sanitizes room numbers" do
        result = subject.call
        expect(result.success?).to be true
        expect(result.room_type.room_numbers).to eq([ "101", "102" ])
        expect(result.room_type).to be_persisted
      end

      it "triggers complete_rooms! on the hotel" do
        expect(hotel).to receive(:complete_rooms!)
        subject.call
      end
    end

    context "when updating an existing room type" do
      let(:room_type) { create(:room_type, hotel: hotel) }
      subject { described_class.new(hotel: hotel, room_type: room_type, params: params) }

      it "updates the room type" do
        result = subject.call
        expect(result.success?).to be true
        expect(room_type.reload.name).to eq("Deluxe Room")
      end

      it "does not trigger complete_rooms! on update" do
        expect(hotel).not_to receive(:complete_rooms!)
        subject.call
      end
    end

    it "returns failure when save fails" do
      params[:name] = nil
      subject = described_class.new(hotel: hotel, params: params)
      result = subject.call
      expect(result.success?).to be false
      expect(result.room_type.errors[:name]).to be_present
    end

    it "does not enqueue structural sync for an undecided provider" do
      hotel.update!(preferred_channel_manager: "undecided")

      expect(ChannelManagers::SyncStructureJob).not_to receive(:perform_later)

      described_class.new(hotel: hotel, params: params).call
    end

    it "does not enqueue structural sync before the selected provider is provisioned" do
      hotel.update!(preferred_channel_manager: "channex")
      hotel.create_channel_mapping!(provider: "channex", external_id: "pending-Hotel-#{hotel.id}")

      expect(ChannelManagers::SyncStructureJob).not_to receive(:perform_later)

      described_class.new(hotel: hotel, params: params).call
    end

    it "enqueues structural sync for a provisioned supported provider" do
      hotel.update!(preferred_channel_manager: "channex")
      hotel.create_channel_mapping!(provider: "channex", external_id: "property-123")

      allow(ChannelManagers::SyncStructureJob).to receive(:perform_later)
      expect(ChannelManagers::SyncStructureJob).to receive(:perform_later).with("RoomType", kind_of(Integer), "sync")

      described_class.new(hotel: hotel, params: params).call
    end
  end
end
