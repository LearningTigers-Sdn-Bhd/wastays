# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::SetVip do
  let!(:hotel) { create(:hotel) }

  describe "#call" do
    it "marks a guest record as VIP" do
      guest = create(:guest, created_by_hotel: hotel, vip: false)

      result = described_class.new(guests: guest, vip: true).call

      expect(result.success?).to be true
      expect(result.changed_count).to eq(1)
      expect(guest.reload.vip).to be true
    end

    it "removes VIP from a guest record" do
      guest = create(:guest, created_by_hotel: hotel, vip: true)

      result = described_class.new(guests: guest, vip: false).call

      expect(result.success?).to be true
      expect(guest.reload.vip).to be false
    end

    it "counts only the records that change" do
      already_vip = create(:guest, created_by_hotel: hotel, vip: true)
      not_vip = create(:guest, created_by_hotel: hotel, vip: false)

      result = described_class.new(guests: [ already_vip, not_vip ], vip: true).call

      expect(result.success?).to be true
      expect(result.changed_count).to eq(1)
      expect(already_vip.reload.vip).to be true
      expect(not_vip.reload.vip).to be true
    end

    it "reports no change when every record already holds the value" do
      guest = create(:guest, created_by_hotel: hotel, vip: true)

      result = described_class.new(guests: guest, vip: true).call

      expect(result.success?).to be true
      expect(result.changed_count).to eq(0)
      expect(result.message).to include("No guest records needed")
    end

    it "fails when nothing is selected" do
      result = described_class.new(guests: [], vip: true).call

      expect(result.success?).to be false
      expect(result.message).to include("No guest records selected")
    end

    it "propagates the flag to the guest's bookings" do
      guest = create(:guest, created_by_hotel: hotel, vip: false)
      booking = create(:booking, hotel: hotel, vip: false)
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      described_class.new(guests: guest, vip: true).call

      expect(booking.reload.vip).to be true
    end
  end
end
