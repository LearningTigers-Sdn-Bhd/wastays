# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::UpdateStatus do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101" ]) }
  let(:room_status) { create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty", priority: false, dnd: false) }

  context "updating priority and notes" do
    it "updates attributes and saves the record" do
      result = described_class.new(
        room_status: room_status,
        params: { priority: "true", notes: "Please clean quickly" },
        user: user
      ).call

      expect(result).to be_success
      room_status.reload
      expect(room_status.priority).to be_truthy
      expect(room_status.notes).to eq("Please clean quickly")
    end
  end

  context "updating DND status" do
    it "sets dnd and current business date when dnd is true" do
      allow(hotel).to receive(:current_business_date).and_return(Date.parse("2026-06-29"))

      result = described_class.new(
        room_status: room_status,
        params: { dnd: "true" },
        user: user
      ).call

      expect(result).to be_success
      room_status.reload
      expect(room_status.dnd).to be_truthy
      expect(room_status.dnd_date).to eq(Date.parse("2026-06-29"))
    end

    it "clears dnd and dnd date when dnd is false" do
      room_status.update!(dnd: true, dnd_date: Date.parse("2026-06-28"))

      result = described_class.new(
        room_status: room_status,
        params: { dnd: "false" },
        user: user
      ).call

      expect(result).to be_success
      room_status.reload
      expect(room_status.dnd).to be_falsy
      expect(room_status.dnd_date).to be_nil
    end
  end

  context "updating physical status" do
    it "calls Rooms::SetStatus when status changes" do
      expect(Rooms::SetStatus).to receive(:new).with(
        room_status: room_status,
        status: "cleaning",
        user: user,
        reason: "Starting to clean"
      ).and_call_original

      result = described_class.new(
        room_status: room_status,
        params: { status: "cleaning", notes: "Starting to clean" },
        user: user
      ).call

      expect(result).to be_success
      expect(room_status.reload.status).to eq("cleaning")
    end

    it "does not call Rooms::SetStatus if status is unchanged" do
      expect(Rooms::SetStatus).not_to receive(:new)

      result = described_class.new(
        room_status: room_status,
        params: { status: "dirty", notes: "No change" },
        user: user
      ).call

      expect(result).to be_success
      expect(room_status.reload.notes).to eq("No change")
    end
  end
end
