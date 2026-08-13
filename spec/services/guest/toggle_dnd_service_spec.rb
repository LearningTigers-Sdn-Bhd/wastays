# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guest::ToggleDndService do
  let(:hotel) { create(:hotel, status: "live") }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: status) }

  subject { described_class.new(booking: booking).call }

  context "when status is not checked_in" do
    let(:status) { "confirmed" }

    it "returns failure and error message" do
      expect(subject.success?).to be false
      expect(subject.error).to eq("Cannot toggle Do Not Disturb if you are not currently checked in.")
    end
  end

  context "when status is checked_in" do
    let(:status) { "checked_in" }

    context "when no room is assigned to the booking" do
      it "returns failure and error message" do
        expect(subject.success?).to be false
        expect(subject.error).to eq("No room assigned to this booking.")
      end
    end

    context "when rooms are assigned" do
      let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, room_number: "101") }

      it "toggles Do Not Disturb preference successfully" do
        room_status = RoomStatus.find_or_create_by!(
          hotel: hotel,
          room_type: room_type,
          room_number: "101"
        )
        expect(room_status.active_dnd?).to be false

        # Toggle ON
        result = described_class.new(booking: booking).call
        expect(result.success?).to be true
        expect(result.message).to eq("Do Not Disturb preference updated successfully.")
        expect(room_status.reload.active_dnd?).to be true

        # Toggle OFF
        result = described_class.new(booking: booking).call
        expect(result.success?).to be true
        expect(result.message).to eq("Do Not Disturb preference updated successfully.")
        expect(room_status.reload.active_dnd?).to be false
      end
    end
  end
end
