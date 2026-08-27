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
        expect(result.room_type.rooms.active.ordered.pluck(:number, :position)).to eq([ [ "101", 0 ], [ "102", 1 ] ])
      end

      it "leaves every new physical room ungrouped, because a group holds rooms" do
        result = subject.call

        expect(result).to be_success
        expect(result.room_type.rooms.active.pluck(:room_group_id)).to contain_exactly(nil, nil)
      end

      it "leaves the hotel's lifecycle status alone" do
        expect { subject.call }.not_to change { hotel.reload.status }
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

      it "rolls back the room type when a physical room conflicts" do
        other_type = create(:room_type, hotel: hotel)
        existing_room = create(:room, hotel: hotel, room_type: other_type, number: "102")
        room_type.update!(quantity: 1)
        original_room = create(:room, hotel: hotel, room_type: room_type, number: "201")

        result = subject.call

        expect(result).not_to be_success
        expect(result.room_type.errors[:room_numbers]).to include("Room 102 already belongs to another room category.")
        expect(RoomType.find(room_type.id)).to have_attributes(quantity: 1, room_numbers: [ "201" ])
        expect(original_room.reload).to be_active
        expect(existing_room.reload.room_type_id).not_to eq(room_type.id)
      end

      it "archives every room when the room type returns to quantity-only inventory" do
        room_type.update!(quantity: 2)
        rooms = %w[201 202].each_with_index.map do |number, position|
          create(:room, hotel: hotel, room_type: room_type, number: number, position: position)
        end

        result = described_class.new(
          hotel: hotel,
          room_type: room_type,
          params: params.merge(room_numbers: [], quantity: 2)
        ).call

        expect(result).to be_success
        expect(room_type.reload.room_numbers).to be_empty
        expect(rooms.map { |room| room.reload }).to all(be_archived)
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

    it "does not enqueue structural sync after room synchronization fails" do
      hotel.update!(preferred_channel_manager: "channex")
      hotel.create_channel_mapping!(provider: "channex", external_id: "property-123")
      other_type = create(:room_type, hotel: hotel)
      create(:room, hotel: hotel, room_type: other_type, number: "102")

      expect(ChannelManagers::SyncStructureJob).not_to receive(:perform_later)

      result = described_class.new(hotel: hotel, params: params).call

      expect(result).not_to be_success
    end
  end
end
