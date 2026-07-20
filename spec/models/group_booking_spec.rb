# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupBooking do
  describe "document identifiers" do
    it "assigns confirmation, reservation, and receipt identifiers from hotel counters" do
      hotel = create(:hotel, hotel_prefix: "HTL")

      group = create(:group_booking, hotel: hotel)
      booking = create(:booking, hotel: hotel)

      expect(group.confirmation_token).to be_present
      expect(group.reservation_number).to eq(1)
      expect(group.receipt_number).to eq(1)
      expect(group.formatted_reservation_number).to eq("HTL-10000001")
      expect(group.formatted_receipt_number).to eq("HTL-50000001")
      expect(booking.reservation_number).to eq(2)
      expect(booking.receipt_number).to eq(2)
    end
  end

  describe "channel identity" do
    it "is unique within a hotel" do
      hotel = create(:hotel)
      create(:group_booking, hotel: hotel, channel_manager_reference: "channel-1", external_reference: "ota-1")

      duplicate = build(:group_booking, hotel: hotel, channel_manager_reference: "channel-1", external_reference: "ota-1")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to include(:channel_manager_reference, :external_reference)
      expect(build(:group_booking, channel_manager_reference: "channel-1", external_reference: "ota-1")).to be_valid
    end
  end
end
