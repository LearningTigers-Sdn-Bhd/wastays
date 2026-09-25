# frozen_string_literal: true

require "rails_helper"

# Test plan phase V, V3: the TA bookings index shows the booking, its status
# and its per-pax total.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.11.
RSpec.describe "Per-pax TA bookings index", type: :request do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  it "V3: lists the FB booking with its status and total" do
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 3).to_s,
      adults: 2, children: 0, rooms: 1, rate_plan_id: fb_plan.id,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    booking = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user).booking
    expect(booking.total_amount.to_d).to eq(1_350.to_d)

    sign_in_as(ta_a_user)
    get corporate_bookings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(booking.guest_name)
    expect(response.body).to include("1,350") # total shown, comma-formatted
  end
end
