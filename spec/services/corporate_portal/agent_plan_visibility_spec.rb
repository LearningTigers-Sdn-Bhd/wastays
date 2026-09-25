# frozen_string_literal: true

require "rails_helper"

# Test plan phase T: TA visibility (who sees which plan).
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.5, table 6c.
RSpec.describe "Per-pax TA plan visibility" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 10 }
  let(:check_out) { check_in + 2 }

  def offered_plans(relationship)
    CorporatePortal::AgentStaySearch.call(
      hotel: hotel, check_in: check_in, check_out: check_out, adults: 2, relationship: relationship
    ).options.select { |o| o.room_type == suite }.map(&:rate_plan)
  end

  # T1: table 6c
  describe "T1: table 6c" do
    it "TA-A sees STD, FB, CORP, PRM (not STAFF/OTA)" do
      expect(offered_plans(ta_a)).to contain_exactly(std_plan, fb_plan, corp_plan, prm_plan)
    end

    it "TA-B sees STD, CORP, PRM but not FB (only -> TA-A)" do
      expect(offered_plans(ta_b)).to contain_exactly(std_plan, corp_plan, prm_plan)
    end

    it "TA-C sees STD, PRM but not FB (only -> TA-A) or CORP (except -> TA-C)" do
      expect(offered_plans(ta_c)).to contain_exactly(std_plan, prm_plan)
    end

    it "no relationship (nil) sees only the plans open to every agency, not an 'All except' plan" do
      expect(offered_plans(nil)).to contain_exactly(std_plan, prm_plan)
      expect(corp_plan.offered_to_agency?(nil)).to be(false)
    end
  end

  # T3: tampered POST - each not-offered plan is refused server-side
  it "T3: CreateAgentBooking refuses a rate_plan_id the agency isn't offered (server-side re-validation)" do
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: check_out.to_s,
      adults: 2, children: 0, rooms: 1, rate_plan_id: fb_plan.id, # TA-C is excluded from FB entirely (only -> TA-A)
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    result = CorporatePortal::CreateAgentBooking.call(relationship: ta_c, params: params, user: ta_c_user)

    expect(result).not_to be_success
  end

  # T4: FB changed only -> all after TA-B searched
  it "T4: TA-B doesn't see FB until it's opened, then does" do
    expect(offered_plans(ta_b)).not_to include(fb_plan)

    fb_plan.update!(ta_access: "all")

    expect(offered_plans(ta_b)).to include(fb_plan)
  end

  # T5: FB changed only -> hidden while TA-A holds a booking; the booking is untouched
  it "T5: an existing FB booking survives the plan being hidden; new FB bookings are refused" do
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: check_out.to_s,
      adults: 2, children: 0, rooms: 1, rate_plan_id: fb_plan.id,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    booked = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user)
    expect(booked).to be_success

    fb_plan.update!(ta_access: "hidden")

    expect(booked.bookings.first.booking_rooms.first.rate_plan_id).to eq(fb_plan.id)
    expect(offered_plans(ta_a)).not_to include(fb_plan)

    new_attempt = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user)
    expect(new_attempt).not_to be_success
  end

  # T6: TA-A removed from FB's list - same effect as T5. "only" with an empty
  # list is refused by validation ("must name at least one travel agent"), so
  # removing the sole agency means adding a different one, not emptying it.
  it "T6: replacing TA-A with TA-B on FB's 'only' list removes TA-A's access" do
    fb_plan.update!(agency_account_ids: [ ta_b.id ])

    expect(offered_plans(ta_a)).not_to include(fb_plan)
    expect(offered_plans(ta_b)).to include(fb_plan)
  end

  # T7: CORP except list changed
  it "T7: changing CORP's except list from [TA-C] to [TA-A, TA-C] moves TA-A to excluded, TA-C stays excluded" do
    expect(offered_plans(ta_a)).to include(corp_plan)

    corp_plan.update!(agency_account_ids: [ ta_a.id, ta_c.id ])

    expect(offered_plans(ta_a)).not_to include(corp_plan)
    expect(offered_plans(ta_c)).not_to include(corp_plan)
  end

  # T8: archived plan offered to nobody
  it "T8: an archived FB plan is offered to nobody" do
    fb_plan.archive!

    expect(offered_plans(ta_a)).not_to include(fb_plan)
  end

  # T9: hidden from public but TA all - independent settings
  it "T9: hiding PRM from the public site does not affect TA visibility" do
    prm_plan.update!(hidden_from_public: true)

    expect(offered_plans(ta_a)).to include(prm_plan)
  end

  # T10: primary plan set on FB is listed first within Suite for TA-A
  it "T10: setting FB as the Suite's primary plan lists it first for TA-A" do
    expect(RatePlans::MakePrimary.call(room_type: suite, rate_plan: fb_plan)).to be_success

    result = CorporatePortal::AgentStaySearch.call(
      hotel: hotel, check_in: check_in, check_out: check_out, adults: 2, relationship: ta_a
    )
    suite_options = result.options.select { |o| o.room_type == suite }

    expect(suite_options.first.rate_plan).to eq(fb_plan)
  end

  # T11: TA-D, an inactive (suspended) relationship
  it "T11: a suspended relationship's search behaviour (RECORDED)" do
    result = CorporatePortal::AgentStaySearch.call(
      hotel: hotel, check_in: check_in, check_out: check_out, adults: 2, relationship: ta_d
    )

    # RECORDED: AgentStaySearch takes any relationship object handed to it and
    # does not itself check `active?` / `may_book_for_clients?` - gating a
    # suspended agency out of search/booking, if it happens, happens at the
    # controller/session layer (sign-in / relationship selection), not here.
    expect(result.options).not_to be_empty # RECORDED: R-T11
  end
end
