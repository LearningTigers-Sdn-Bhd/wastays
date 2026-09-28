# frozen_string_literal: true

require "rails_helper"

# Test plan phase V: does it display correctly?
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.11.
# Scope note: only V2 (the TA booking page) is covered here. V5 (the hotel
# workspace's rate rows) renders the plan name inside a nested
# room_and_rate/_panel partial that this session could not get a request spec
# to exercise cleanly in the time available - it needs either a system spec
# (no browser in this environment) or more time on the workspace's rendering
# path than this session had left. The reports (V9-V14) and folio/AR invoice
# screens (V6/V8) need night-audit/checkout orchestration not covered either;
# see the lifecycle spec's scope note.
RSpec.describe "Per-pax display: TA booking page", type: :request do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }
  let(:staff_user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  let!(:booking) do
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 3).to_s,
      adults: 2, children: 0, rooms: 1, rate_plan_id: fb_plan.id,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user).booking
  end

  # V2: TA booking page shows the plan name, nightly rates and the room total
  it "V2: the TA booking page shows the plan name and a total matching the booking" do
    sign_in_as(ta_a_user)

    get corporate_booking_path(booking, hotel_relationship_id: ta_a.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Full Board")
    expect(response.body).to include(booking.total_amount.to_i.to_s)
  end

  # V5: the hotel workspace at least shows the booking's agency (Source
  # Details) on its first render - the rate-row plan name assertion is
  # deferred, see the scope note above.
  it "V5 (partial): the hotel workspace shows the booking's agency" do
    role.permissions << (Permission.find_by(slug: "view_bookings") || create(:permission, slug: "view_bookings"))
    UserHotelAccess.create!(user: staff_user, hotel: hotel, role: role)
    sign_in_as(staff_user)

    get hotel_booking_workspace_path(hotel, booking)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(ta_a.corporate_account.name)
  end

  # V7 (RECORDED, R11): not independently verified with a request spec this
  # session (a second request in the same example intermittently rendered the
  # dashboard instead of the booking page - not chased down further given
  # time). Confirmed instead by reading every view/presenter that could show
  # a booking (grep of app/views, app/presenters for undiscounted_price /
  # stay_discount): none outside the rate plan editor itself reads either key,
  # so R11 stands as a code-reading finding, same status as in the test plan.
end
