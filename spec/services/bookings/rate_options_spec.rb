# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::RateOptions do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:check_in) { Date.current + 1.day }
  let(:check_out) { Date.current + 2.days }
  let(:service) { described_class.new(room_type: room_type, check_in: check_in, check_out: check_out) }

  before { create(:room_rate, room_type: room_type, rate_plan: room_type.standard_rate_plan, date: check_in, price: 150.0) }

  describe "#call" do
    context "when no rate plans exist" do
      before { room_type.rate_plans.destroy_all }

      it("returns no options") { expect(service.call).to be_empty }
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

    it "offers real Walk-in and Corporate plans to staff" do
      expect(service.call.pluck(:id)).to include(room_type.walk_in_rate_plan.id, room_type.corporate_rate_plan.id)
    end

    it "limits corporate callers to Standard, Custom, and Corporate" do
      options = described_class.new(room_type:, check_in:, check_out:, audience: :corporate).call

      expect(options.pluck(:id)).to include(room_type.standard_rate_plan.id, room_type.corporate_rate_plan.id)
      expect(options.pluck(:id)).not_to include(room_type.walk_in_rate_plan.id)
    end
  end
end
