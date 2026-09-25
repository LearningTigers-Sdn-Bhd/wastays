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

    get new_corporate_booking_path(hotel_relationship_id: ta_a.id, check_in: check_in, check_out: check_in + 3, adults: 2)

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include("Not bookable for these dates")
    expect(page.text).to include("Closed for sale on #{(check_in + 1).strftime('%-d %b')}")
    expect(page.css("a[href*='rate_plan_id=#{fb_plan.id}&'][href*='room_type_id=#{suite.id}&']")).to be_empty
    expect(page.css("a[href*='rate_plan_id=#{prm_plan.id}&'][href*='room_type_id=#{suite.id}&']")).not_to be_empty
  end

  it "does not open the guest details form for a restricted plan reached by URL" do
    create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in, price: 500, min_stay: 5)
    sign_in_as(ta_a_user)

    get new_corporate_booking_path(hotel_relationship_id: ta_a.id, check_in: check_in, check_out: check_in + 3,
                                   adults: 2, room_type_id: suite.id, rate_plan_id: fb_plan.id)

    expect(response.body).to include("Minimum stay 5 nights")
    expect(response.body).not_to include("Guest details")
  end
end
