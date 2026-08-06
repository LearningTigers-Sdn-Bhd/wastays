# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::GuestRegistrationCardsQuery do
  let(:hotel) { create(:hotel) }
  let(:booking1) { create(:booking, hotel: hotel, check_in: Date.current, guest_name: "John Doe", confirmation_token: "CONF1") }
  let(:booking2) { create(:booking, hotel: hotel, check_in: Date.current + 1.day, guest_name: "Jane Smith", confirmation_token: "CONF2") }

  let!(:card1) { create(:guest_registration_card, booking: booking1, hotel: hotel, status: "draft") }
  let!(:card2) { create(:guest_registration_card, booking: booking2, hotel: hotel, status: "signed", signer_name: "Jane Smith", signature_data_url: "data:image/png;base64,123") }

  describe "#results" do
    it "returns all cards ordered by check-in descending" do
      query = described_class.new(hotel: hotel)
      expect(query.results).to eq([ card2, card1 ])
    end

    it "filters by status" do
      query = described_class.new(hotel: hotel, status: "signed")
      expect(query.results).to eq([ card2 ])
    end

    it "filters by date range" do
      query = described_class.new(hotel: hotel, start_date: Date.current, end_date: Date.current)
      expect(query.results).to eq([ card1 ])
    end

    it "filters by search query" do
      query = described_class.new(hotel: hotel, query: "John")
      expect(query.results).to eq([ card1 ])
    end
  end

  describe "#total_count, #signed_count, #draft_count" do
    it "computes correct counts" do
      query = described_class.new(hotel: hotel)
      expect(query.total_count).to eq(2)
      expect(query.signed_count).to eq(1)
      expect(query.draft_count).to eq(1)
    end
  end
end
