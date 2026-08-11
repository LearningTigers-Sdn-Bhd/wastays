# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::RateSelection do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let!(:rate_plan) { create(:rate_plan, hotel: hotel, room_type: room_type) }

  describe ".resolve" do
    it "returns a standard selection for a blank value" do
      selection = described_class.resolve(room_type: room_type, value: "")

      expect(selection).to have_attributes(rate_plan: nil, token: "")
    end

    it "resolves a plain rate-plan id to a standard-tier selection" do
      selection = described_class.resolve(room_type: room_type, value: rate_plan.id.to_s)

      expect(selection).to have_attributes(rate_plan: rate_plan, token: rate_plan.id.to_s)
    end

    it "returns a standard selection when the rate-plan id is unknown" do
      selection = described_class.resolve(room_type: room_type, value: "0")

      expect(selection).to have_attributes(rate_plan: nil, token: "")
    end

    it "rejects a non-plan token" do
      selection = described_class.resolve(room_type: room_type, value: "not-a-plan")

      expect(selection).to have_attributes(rate_plan: nil, token: "")
    end

    it "rejects an archived rate plan" do
      rate_plan.archive!

      selection = described_class.resolve(room_type: room_type, value: rate_plan.id)

      expect(selection).to have_attributes(rate_plan: nil, token: "")
    end
  end

  describe ".current" do
    it "reports the standard tier for a booking room on a plain rate plan" do
      booking = create(:booking, hotel: hotel)
      booking_room = create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan)

      selection = described_class.current(booking_room)

      expect(selection).to have_attributes(rate_plan: rate_plan, token: rate_plan.id.to_s)
    end
  end
end
