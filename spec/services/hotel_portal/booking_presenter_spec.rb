# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::BookingPresenter do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  subject { described_class.new(booking, hotel) }

  describe "#pending_requests_count" do
    it "returns the total of pending housekeeping and complaint requests" do
      create(:housekeeping_request, booking: booking, status: "pending")
      create(:housekeeping_request, booking: booking, status: "completed")
      create(:complaint_request, booking: booking, status: "pending")
      create(:complaint_request, booking: booking, status: "resolved")

      expect(subject.pending_requests_count).to eq(2)
    end
  end

  describe "#housekeeping_requests" do
    it "returns active or cancelled housekeeping requests" do
      req1 = create(:housekeeping_request, booking: booking, status: "pending")
      req2 = create(:housekeeping_request, booking: booking, status: "cancelled")
      create(:housekeeping_request, booking: booking, status: "completed", archived_at: Time.current)

      expect(subject.housekeeping_requests).to contain_exactly(req1, req2)
    end
  end

  describe "#complaint_requests" do
    it "returns active or cancelled complaint requests" do
      req1 = create(:complaint_request, booking: booking, status: "pending")
      req2 = create(:complaint_request, booking: booking, status: "cancelled")
      create(:complaint_request, booking: booking, status: "resolved", archived_at: Time.current)

      expect(subject.complaint_requests).to contain_exactly(req1, req2)
    end
  end
end
