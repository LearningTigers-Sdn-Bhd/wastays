# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::BillTravelAgentPackage do
  let(:booking) { create(:booking) }
  let(:hotel) { booking.hotel }
  let(:actor) { create(:user, account: hotel.account) }
  let(:corporate_account) { create(:hotel_corporate_account, hotel: hotel) }

  before do
    Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: actor, lock: false)
  end

  describe ".codes_for" do
    it "returns room revenue and package extra charge codes" do
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      package_extra = create(:hotel_extra_charge, hotel: hotel, bill_to_travel_agent: true)
      _regular_extra = create(:hotel_extra_charge, hotel: hotel, bill_to_travel_agent: false)

      codes = described_class.codes_for(hotel)

      expect(codes).to include(room_code, package_extra.transaction_code)
    end
  end

  describe "#call" do
    it "routes room charges and package extras to the agent folio, leaving regular extras unrouted" do
      jetty_fee = create(:hotel_extra_charge, hotel: hotel, bill_to_travel_agent: true)
      cake = create(:hotel_extra_charge, hotel: hotel, bill_to_travel_agent: false)

      result = described_class.call(booking: booking, actor: actor, hotel_corporate_account_id: corporate_account.id)

      expect(result.success?).to be(true)
      agent_folio = result.target_folio
      expect(agent_folio).to have_attributes(folio_type: "external", payer_type: "company",
        hotel_corporate_account_id: corporate_account.id)

      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      rules = booking.folio_routing_rules.active.to_h { |rule| [ rule.transaction_code_id, rule.target_folio_id ] }

      expect(rules[room_code.id]).to eq(agent_folio.id)
      expect(rules[jetty_fee.transaction_code_id]).to eq(agent_folio.id)
      expect(rules).not_to have_key(cake.transaction_code_id)
    end

    it "invokes RerouteScheduledExtras when package extras are configured" do
      create(:hotel_extra_charge, hotel: hotel, bill_to_travel_agent: true)
      allow(Folios::Routing::RerouteScheduledExtras).to receive(:call)

      described_class.call(booking: booking, actor: actor, hotel_corporate_account_id: corporate_account.id)

      expect(Folios::Routing::RerouteScheduledExtras).to have_received(:call).with(booking: booking)
    end

    it "fails when the corporate account is not valid for the hotel" do
      result = described_class.call(booking: booking, actor: actor, hotel_corporate_account_id: 0)

      expect(result.success?).to be(false)
      expect(result.error).to be_present
    end
  end
end
