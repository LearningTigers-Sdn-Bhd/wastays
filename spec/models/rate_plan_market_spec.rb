# frozen_string_literal: true

require "rails_helper"

# Local and international travel agents are offered different rates. A plan marked
# for one market is hidden from the other, and from an agent with no market set.
RSpec.describe RatePlan, "agent markets" do
  let(:hotel) { create(:hotel) }

  def plan(name, ta_market: "all", ta_access: "all")
    create(:rate_plan, :custom, hotel: hotel, name: name, ta_access: ta_access, ta_market: ta_market)
  end

  def agency(market) = create(:hotel_corporate_account, hotel: hotel, market: market)

  let!(:everyone) { plan("Open Rate") }
  let!(:local_rate) { plan("Malaysian Agent Rate", ta_market: "local") }
  let!(:international_rate) { plan("International Agent Rate", ta_market: "international") }

  it "offers a local agent the local plans and the open ones, never the international ones" do
    offered = hotel.rate_plans.offered_to_agency(agency("local"))

    expect(offered).to include(everyone, local_rate)
    expect(offered).not_to include(international_rate)
  end

  it "offers an international agent the international plans and the open ones, never the local ones" do
    offered = hotel.rate_plans.offered_to_agency(agency("international"))

    expect(offered).to include(everyone, international_rate)
    expect(offered).not_to include(local_rate)
  end

  it "offers an agent with no market set only the plans open to every market" do
    offered = hotel.rate_plans.offered_to_agency(agency(nil))

    expect(offered).to include(everyone)
    expect(offered).not_to include(local_rate, international_rate)
  end

  it "still applies the access rule inside a market" do
    only_named = plan("Local Only These", ta_market: "local", ta_access: "only")
    local_agent = agency("local")

    expect(hotel.rate_plans.offered_to_agency(local_agent)).not_to include(only_named)

    only_named.rate_plan_agency_rules.create!(hotel_corporate_account: local_agent)
    expect(hotel.rate_plans.offered_to_agency(local_agent)).to include(only_named)
  end

  it "answers the same through offered_to_agency? for a plan in hand" do
    local_agent = agency("local")

    expect(local_rate.offered_to_agency?(local_agent)).to be(true)
    expect(international_rate.offered_to_agency?(local_agent)).to be(false)
    expect(local_rate.offered_to_agency?(agency(nil))).to be(false)
  end

  it "rejects a market it does not know" do
    expect(build(:rate_plan, hotel: hotel, ta_market: "martian")).not_to be_valid
    expect(build(:hotel_corporate_account, hotel: hotel, market: "martian")).not_to be_valid
  end

  it "reads a blank market as not set" do
    expect(create(:hotel_corporate_account, hotel: hotel, market: "").market).to be_nil
  end
end
