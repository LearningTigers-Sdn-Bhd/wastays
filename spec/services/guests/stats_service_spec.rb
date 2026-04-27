# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::StatsService do
  let(:hotel) { create(:hotel) }
  let(:guest1) { create(:guest) }
  let(:guest2) { create(:guest) }

  before do
    b1 = create(:booking, hotel: hotel, total_amount: 100, currency: "MYR")
    create(:booking_guest, booking: b1, guest: guest1, is_primary: true)

    b2 = create(:booking, hotel: hotel, total_amount: 150, currency: "MYR")
    create(:booking_guest, booking: b2, guest: guest1, is_primary: true)

    b3 = create(:booking, hotel: hotel, total_amount: 50, currency: "USD")
    create(:booking_guest, booking: b3, guest: guest2, is_primary: true)
  end

  describe "#call" do
    let(:service) { described_class.new(hotel: hotel, guest_ids: [ guest1.id, guest2.id ]) }
    let(:result) { service.call }

    it "calculates stays count correctly" do
      expect(result[:stays_count][guest1.id]).to eq(2)
      expect(result[:stays_count][guest2.id]).to eq(1)
    end

    it "calculates currency totals correctly" do
      expect(result[:currency_totals][guest1.id]["MYR"]).to eq(250)
      expect(result[:currency_totals][guest2.id]["USD"]).to eq(50)
    end
  end
end
