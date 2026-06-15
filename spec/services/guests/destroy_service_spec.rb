# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::DestroyService do
  let!(:hotel) { create(:hotel) }
  let!(:other_hotel) { create(:hotel) }
  let!(:guest) { create(:guest, created_by_hotel: hotel) }
  let(:service) { described_class.new(guest: guest, hotel: hotel) }

  describe "#call" do
    context "when guest has active bookings at the hotel" do
      before do
        booking = create(:booking, hotel: hotel, status: "confirmed")
        create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      end

      it "returns success (because it is a soft delete)" do
        result = service.call
        expect(result.success?).to be true
        expect(result.message).to include("removed successfully")
      end

      it "soft deletes the guest (hides from kept scope but remains in DB)" do
        expect { service.call }.to change { Guest.kept.count }.by(-1)
        expect(Guest.exists?(guest.id)).to be true
        expect(guest.reload.discarded?).to be true
      end
    end

    context "when guest has only cancelled bookings at the hotel" do
      before do
        booking = create(:booking, hotel: hotel, status: "cancelled")
        create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      end

      it "returns success" do
        result = service.call
        expect(result.success?).to be true
      end

      it "soft deletes the guest record" do
        expect { service.call }.to change { Guest.kept.count }.by(-1)
        expect(Guest.exists?(guest.id)).to be true
        expect(guest.reload.discarded?).to be true
      end
    end

    context "when guest has no bookings at the hotel" do
      context "when guest was created by the hotel" do
        it "returns success" do
          result = service.call
          expect(result.success?).to be true
          expect(result.message).to include("removed successfully")
        end

        it "soft deletes the guest record" do
          expect { service.call }.to change { Guest.kept.count }.by(-1)
          expect(Guest.exists?(guest.id)).to be true
          expect(guest.reload.discarded?).to be true
        end
      end
    end
  end
end
