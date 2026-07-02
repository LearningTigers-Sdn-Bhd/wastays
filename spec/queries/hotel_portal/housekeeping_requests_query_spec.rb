# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::HousekeepingRequestsQuery do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:room_number) { "101" }

  describe "#call" do
    subject { described_class.new(hotel: hotel, room_number: room_number).call }

    context "when hotel is nil" do
      let(:hotel) { nil }
      it { is_expected.to be_empty }
    end

    context "when room_number is blank" do
      let(:room_number) { "" }
      it { is_expected.to be_empty }
    end

    context "when hotel and room_number are present" do
      let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
      let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, room_number: "101") }

      let!(:in_progress_request) do
        create(:housekeeping_request, booking: booking, status: "in_progress", archived_at: nil)
      end

      let!(:completed_request) do
        create(:housekeeping_request, booking: booking, status: "completed", archived_at: nil)
      end

      let!(:archived_request) do
        create(:housekeeping_request, booking: booking, status: "in_progress", archived_at: Time.current)
      end

      it "returns only active (not archived) and in-progress requests for the room and hotel" do
        expect(subject).to contain_exactly(in_progress_request)
      end

      context "when booking is for a different hotel" do
        let(:other_hotel) { create(:hotel, status: "approved") }
        let(:other_booking) { create(:booking, hotel: other_hotel, status: "checked_in") }
        let!(:other_booking_room) { create(:booking_room, booking: other_booking, room_type: room_type, room_number: "101") }
        let!(:other_request) do
          create(:housekeeping_request, booking: other_booking, status: "in_progress", archived_at: nil)
        end

        it "does not include requests from other hotels" do
          expect(subject).to contain_exactly(in_progress_request)
        end
      end
    end
  end
end
