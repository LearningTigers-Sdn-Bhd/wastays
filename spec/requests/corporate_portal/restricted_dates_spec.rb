# frozen_string_literal: true

require "rails_helper"

# A plan the property closed for the searched dates is shown to the agent with
# the reason, but offers nothing to select or book.
RSpec.describe "Corporate portal search: restricted dates", type: :request do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  it "lists a stop-sell plan as not bookable, with the reason and no Select link" do
    create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in + 1, price: 500, stop_sell: true)
    sign_in_as(ta_a_user)

    get new_corporate_booking_path(hotel_relationship_id: ta_a.id, check_in: check_in, check_out: check_in + 3,
                                   step: "rooms", stage: "rate", add_room_type_id: suite.id, add_adults: 2, add_quantity: 1)

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    # The category has another plan open, so the closed one is listed under its rates.
    expect(page.text).to include("Closed for sale on #{(check_in + 1).strftime('%-d %b')}")
    # "Add to stay" puts the chosen rate into the cart's line, so the rates on offer
    # are the ones those links carry.
    offered = page.css("[data-testid='select-rate']").map do |link|
      Rack::Utils.parse_nested_query(URI(link["href"]).query).dig("lines", "0", "rate_plan_id").to_i
    end
    expect(offered).not_to include(fb_plan.id)
    expect(offered).to include(prm_plan.id)
  end

  it "does not open the guest details form for a restricted plan reached by URL" do
    create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in, price: 500, min_stay: 5)
    sign_in_as(ta_a_user)

    get new_corporate_booking_path(hotel_relationship_id: ta_a.id, check_in: check_in, check_out: check_in + 3, step: "guests",
                                   lines: { "0" => { room_type_id: suite.id, rate_plan_id: fb_plan.id, adults: 2, quantity: 1 } })

    expect(response.body).to include("Minimum stay 5 nights")
    expect(response.body).not_to include("Guest details")
  end
end
