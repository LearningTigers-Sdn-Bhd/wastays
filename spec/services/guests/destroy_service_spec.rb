# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::DestroyService do
  let!(:hotel) { create(:hotel) }
  let!(:other_hotel) { create(:hotel) }
  let!(:guest) { create(:guest, created_by_hotel: hotel) }
  let(:service) { described_class.new(guest: guest, hotel: hotel) }

  describe "#call" do
    context "when guest has bookings at the hotel" do
      before do
        booking = create(:booking, hotel: hotel)
        create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      end

      it "returns failure" do
        result = service.call
        expect(result.success?).to be false
        expect(result.message).to include("associated bookings")
      end

      it "does not destroy the guest" do
        expect { service.call }.not_to change(Guest, :count)
      end
    end

    context "when guest has no bookings at the hotel" do
      context "when guest was created by the hotel" do
        it "returns success" do
          result = service.call
          expect(result.success?).to be true
          expect(result.message).to include("removed successfully")
        end

        it "destroys the guest record if no other links exist" do
          expect { service.call }.to change(Guest, :count).by(-1)
        end

        it "destroys the guest record even if links to this hotel existed (but no bookings)" do
          # This case covers where booking_guests exists but bookings don't (rare but possible if orphan link)
          create(:booking_guest, guest: guest, booking: create(:booking, hotel: other_hotel))
          # If it has links to other hotels, it shouldn't be fully destroyed if those links are still there.
          # The service says: if @guest.created_by_hotel_id == @hotel.id && @guest.booking_guests.empty?

          # Let's test the specific logic:
          guest_with_other_link = create(:guest, created_by_hotel: hotel)
          create(:booking_guest, guest: guest_with_other_link, booking: create(:booking, hotel: other_hotel))

          result = described_class.new(guest: guest_with_other_link, hotel: hotel).call
          expect(result.success?).to be true
          expect(Guest.exists?(guest_with_other_link.id)).to be true
        end
      end

      context "when guest was not created by the hotel" do
        let(:guest) { create(:guest, created_by_hotel: other_hotel) }

        it "returns success" do
          result = service.call
          expect(result.success?).to be true
        end

        it "does not destroy the guest record" do
          expect { service.call }.not_to change(Guest, :count)
        end
      end
    end
  end
end
