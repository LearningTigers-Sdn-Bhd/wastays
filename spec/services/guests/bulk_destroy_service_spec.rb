# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::BulkDestroyService do
  let!(:hotel) { create(:hotel) }
  let!(:other_hotel) { create(:hotel) }

  let!(:guest1) { create(:guest, created_by_hotel: hotel) }
  let!(:guest2) { create(:guest, created_by_hotel: hotel) }
  let!(:other_guest) { create(:guest, created_by_hotel: other_hotel) }

  describe "#call" do
    context "when all selected guest records are valid for the hotel" do
      let(:service) { described_class.new(guest_ids: [ guest1.id, guest2.id ], hotel: hotel) }

      it "returns success" do
        result = service.call
        expect(result.success?).to be true
        expect(result.message).to include("removed successfully")
      end

      it "soft deletes the valid guest records" do
        expect { service.call }.to change { Guest.kept.count }.by(-2)
        expect(guest1.reload.discarded?).to be true
        expect(guest2.reload.discarded?).to be true
      end
    end

    context "when some selected guests are not associated with the hotel" do
      let(:service) { described_class.new(guest_ids: [ guest1.id, other_guest.id ], hotel: hotel) }

      it "returns success for the allowed ones" do
        result = service.call
        expect(result.success?).to be true
      end

      it "only soft deletes guests belonging to the hotel" do
        expect { service.call }.to change { Guest.kept.count }.by(-1)
        expect(guest1.reload.discarded?).to be true
        expect(other_guest.reload.discarded?).to be false
      end
    end

    context "when guest has a booking at the hotel but was created by another" do
      let!(:guest_with_booking) { create(:guest, created_by_hotel: other_hotel) }
      let(:service) { described_class.new(guest_ids: [ guest_with_booking.id ], hotel: hotel) }

      before do
        booking = create(:booking, hotel: hotel, status: "confirmed")
        create(:booking_guest, booking: booking, guest: guest_with_booking, is_primary: true)
      end

      it "returns success and soft deletes the guest" do
        result = service.call
        expect(result.success?).to be true
        expect(guest_with_booking.reload.discarded?).to be true
      end
    end

    context "when none of the selected guests are associated with the hotel" do
      let(:service) { described_class.new(guest_ids: [ other_guest.id ], hotel: hotel) }

      it "returns failure" do
        result = service.call
        expect(result.success?).to be false
        expect(result.message).to include("No valid guest records selected")
      end

      it "does not soft delete any guest" do
        expect { service.call }.not_to change { Guest.kept.count }
        expect(other_guest.reload.discarded?).to be false
      end
    end
  end
end
