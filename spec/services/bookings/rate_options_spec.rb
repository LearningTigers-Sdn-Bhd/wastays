# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::RateOptions do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:check_in) { Date.current + 1.day }
  let(:check_out) { Date.current + 2.days }
  let(:service) { described_class.new(room_type: room_type, check_in: check_in, check_out: check_out) }

  before do
    create(:room_rate, room_type: room_type, date: check_in, price: 150.0)
  end

  describe "#call" do
    context "when no rate plans exist" do
      before { room_type.rate_plans.destroy_all }

      it "returns base rate option" do
        options = service.call
        expect(options.size).to eq(1)
        expect(options.first[:name]).to eq("Base Rate")
        expect(options.first[:total_amount]).to eq("150.0")
      end
    end

    context "when rate plans exist" do
      let!(:rate_plan) { create(:rate_plan, room_type: room_type, name: "Special Offer") }

      before do
        create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: check_in, price: 120.0)
      end

      it "returns rate plan options" do
        options = service.call
        expect(options.any? { |o| o[:name] == "Special Offer" }).to be true
      end

      it "filters restricted plans if requested" do
        room_type.room_rates.find_by(rate_plan: rate_plan).update!(stop_sell: true)

        # Without apply_stop_sell: true
        expect(service.call.any? { |o| o[:name] == "Special Offer" }).to be true

        # With apply_stop_sell: true
        restricted_service = described_class.new(
          room_type: room_type,
          check_in: check_in,
          check_out: check_out,
          apply_stop_sell: true
        )
        expect(restricted_service.call.any? { |o| o[:name] == "Special Offer" }).to be false
      end
    end
  end
end
