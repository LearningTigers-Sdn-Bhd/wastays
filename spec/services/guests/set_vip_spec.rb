# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::SetVip do
  let!(:hotel) { create(:hotel) }
  let!(:other_hotel) { create(:hotel) }

  describe "#call" do
    context "when it marks VIP" do
      it "records the property id" do
        guest = create(:guest, created_by_hotel: hotel)

        result = described_class.new(guests: guest, hotel: hotel, vip: true).call

        expect(result.success?).to be true
        expect(result.changed_count).to eq(1)

        guest.reload
        expect(guest.vip).to be true
        expect(guest.vip_at?(hotel)).to be true
        expect(guest.metadata["vip_hotel_ids"]).to eq([ hotel.id ])
      end

      it "leaves the guest record plain at another property" do
        guest = create(:guest, created_by_hotel: hotel)

        described_class.new(guests: guest, hotel: hotel, vip: true).call

        expect(guest.reload.vip_at?(other_hotel)).to be false
      end

      it "does not add the same property twice" do
        guest = create(:guest, created_by_hotel: hotel)

        described_class.new(guests: guest, hotel: hotel, vip: true).call
        result = described_class.new(guests: guest, hotel: hotel, vip: true).call

        expect(result.changed_count).to eq(0)
        expect(guest.reload.metadata["vip_hotel_ids"]).to eq([ hotel.id ])
      end
    end

    context "when it removes VIP" do
      it "drops the property id" do
        guest = create(:guest, created_by_hotel: hotel)
        described_class.new(guests: guest, hotel: hotel, vip: true).call

        result = described_class.new(guests: guest, hotel: hotel, vip: false).call

        expect(result.success?).to be true
        guest.reload
        expect(guest.vip).to be false
        expect(guest.vip_at?(hotel)).to be false
        expect(guest.metadata["vip_hotel_ids"]).to eq([])
      end

      it "keeps the column true while another property still holds the flag" do
        guest = create(:guest, created_by_hotel: hotel)
        described_class.new(guests: guest, hotel: hotel, vip: true).call
        described_class.new(guests: guest, hotel: other_hotel, vip: true).call

        described_class.new(guests: guest, hotel: hotel, vip: false).call

        guest.reload
        expect(guest.vip).to be true
        expect(guest.vip_at?(hotel)).to be false
        expect(guest.vip_at?(other_hotel)).to be true
      end

      it "removes the flag from one property only on a legacy record" do
        guest = create(:guest, created_by_hotel: nil, vip: true, metadata: {})
        booking = create(:booking, hotel: hotel)
        other_booking = create(:booking, hotel: other_hotel)
        create(:booking_guest, booking: booking, guest: guest, is_primary: true)
        create(:booking_guest, booking: other_booking, guest: guest, is_primary: true)
        expect(guest.vip_at?(other_hotel)).to be true

        described_class.new(guests: guest, hotel: hotel, vip: false).call

        guest.reload
        expect(guest.vip_at?(hotel)).to be false
        expect(guest.vip_at?(other_hotel)).to be true
      end
    end

    context "with more than one guest record" do
      it "counts only the records that change" do
        already = create(:guest, created_by_hotel: hotel)
        described_class.new(guests: already, hotel: hotel, vip: true).call
        fresh = create(:guest, created_by_hotel: hotel)

        result = described_class.new(guests: [ already, fresh ], hotel: hotel, vip: true).call

        expect(result.changed_count).to eq(1)
        expect(fresh.reload.vip_at?(hotel)).to be true
      end
    end

    it "propagates to that property's bookings only" do
      guest = create(:guest, created_by_hotel: hotel)
      booking = create(:booking, hotel: hotel, vip: false)
      other_booking = create(:booking, hotel: other_hotel, vip: false)
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      create(:booking_guest, booking: other_booking, guest: guest, is_primary: true)

      described_class.new(guests: guest, hotel: hotel, vip: true).call

      expect(booking.reload.vip).to be true
      expect(other_booking.reload.vip).to be false
    end

    it "fails when nothing is selected" do
      result = described_class.new(guests: [], hotel: hotel, vip: true).call

      expect(result.success?).to be false
      expect(result.message).to include("No guest records selected")
    end
  end
end
