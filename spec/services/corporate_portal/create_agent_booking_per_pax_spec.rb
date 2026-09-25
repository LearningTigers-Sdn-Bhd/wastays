# frozen_string_literal: true

require "rails_helper"

# Test plan phase C: the TA booking follows the plan.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.6.
RSpec.describe "Per-pax TA booking follows the plan" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  def book(plan:, adults:, children: 0, nights: 1, relationship: ta_a, actor: ta_a_user, room_type: suite)
    params = {
      room_type_id: room_type.id, check_in: check_in.to_s, check_out: (check_in + nights).to_s,
      adults: adults, children: children, rooms: 1, rate_plan_id: plan.id,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    CorporatePortal::CreateAgentBooking.call(relationship: relationship, params: params, user: actor)
  end

  def search_total(plan:, adults:, children: 0, nights: 1, relationship: ta_a)
    result = CorporatePortal::AgentStaySearch.call(
      hotel: hotel, check_in: check_in, check_out: check_in + nights, adults: adults, children: children,
      relationship: relationship
    )
    result.options.find { |o| o.rate_plan == plan && o.room_type == suite }
  end

  # C1: table-driven, every plan TA-A can see x every party x 1/3/5 nights
  describe "C1: search quote = booked total = nightly snapshot sum, for every plan x party x nights" do
    combinations = [
      # [plan_key, adults, children, nights, expected_total]
      [ :std, 1, 0, 1, 250 ], [ :std, 1, 0, 3, 750 ], [ :std, 1, 0, 5, 1250 ],
      [ :std, 2, 0, 1, 440 ], [ :std, 2, 0, 3, 1320 ], [ :std, 2, 0, 5, 2200 ],
      [ :std, 3, 0, 1, 600 ], [ :std, 3, 0, 3, 1800 ], [ :std, 3, 0, 5, 3000 ],
      [ :std, 4, 0, 1, 740 ], [ :std, 4, 0, 3, 2220 ], [ :std, 4, 0, 5, 3700 ],
      [ :std, 2, 1, 1, 660 ], [ :std, 2, 1, 3, 1980 ], [ :std, 2, 1, 5, 3300 ],

      [ :fb, 1, 0, 1, 300 ], [ :fb, 1, 0, 3, 810 ], [ :fb, 1, 0, 5, 1420 ],
      [ :fb, 2, 0, 1, 500 ], [ :fb, 2, 0, 3, 1350 ], [ :fb, 2, 0, 5, 2340 ],
      [ :fb, 3, 0, 1, 690 ], [ :fb, 3, 0, 3, 1863 ], [ :fb, 3, 0, 5, 3210 ],
      [ :fb, 4, 0, 1, 840 ], [ :fb, 4, 0, 3, 2268 ], [ :fb, 4, 0, 5, 3880 ],
      [ :fb, 2, 1, 1, 750 ], [ :fb, 2, 1, 3, 2025 ], [ :fb, 2, 1, 5, 3510 ],

      [ :corp, 1, 0, 1, 225 ], [ :corp, 1, 0, 3, 675 ], [ :corp, 1, 0, 5, 1125 ],
      [ :corp, 2, 0, 1, 396 ], [ :corp, 2, 0, 3, 1188 ], [ :corp, 2, 0, 5, 1980 ],
      [ :corp, 3, 0, 1, 540 ], [ :corp, 3, 0, 3, 1620 ], [ :corp, 3, 0, 5, 2700 ],
      [ :corp, 4, 0, 1, 666 ], [ :corp, 4, 0, 3, 1998 ], [ :corp, 4, 0, 5, 3330 ],
      [ :corp, 2, 1, 1, 594 ], [ :corp, 2, 1, 3, 1782 ], [ :corp, 2, 1, 5, 2970 ],

      [ :prm, 1, 0, 1, 336 ], [ :prm, 1, 0, 3, 1008 ], [ :prm, 1, 0, 5, 1680 ],
      [ :prm, 2, 0, 1, 480 ], [ :prm, 2, 0, 3, 1440 ], [ :prm, 2, 0, 5, 2400 ],
      [ :prm, 3, 0, 1, 630 ], [ :prm, 3, 0, 3, 1890 ], [ :prm, 3, 0, 5, 3150 ],
      [ :prm, 4, 0, 1, 780 ], [ :prm, 4, 0, 3, 2340 ], [ :prm, 4, 0, 5, 3900 ],
      [ :prm, 2, 1, 1, 720 ], [ :prm, 2, 1, 3, 2160 ], [ :prm, 2, 1, 5, 3600 ]
    ]

    combinations.each do |plan_key, adults, children, nights, expected|
      it "#{plan_key} #{adults}A#{"+#{children}C" if children.positive?} x #{nights}n = #{expected}" do
        plan = send(:"#{plan_key}_plan")

        option = search_total(plan: plan, adults: adults, children: children, nights: nights)
        expect(option).to be_present
        expect(option.per_room_amount).to eq(expected.to_d)

        result = book(plan: plan, adults: adults, children: children, nights: nights)
        expect(result).to be_success, Array(result.errors).to_sentence

        booking = result.booking
        expect(booking.total_amount.to_d).to eq(expected.to_d)
        expect(booking.total_amount.to_d).to eq(option.per_room_amount)

        snapshot = booking.booking_rooms.first.nightly_rate_snapshot
        expect(snapshot.size).to eq(nights)
        expect(snapshot.values.sum { |n| n["price"].to_d }).to eq(expected.to_d)
      end
    end
  end

  # C2: attribution
  it "C2: attributes the booking to the agency, the person, the plan and a truncated agent_reference" do
    result = book(plan: fb_plan, adults: 2, nights: 1)
    result = CorporatePortal::CreateAgentBooking.call(
      relationship: ta_a, user: ta_a_user,
      params: {
        room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 1).to_s,
        adults: 2, children: 0, rooms: 1, rate_plan_id: fb_plan.id, agent_reference: "X" * 150,
        rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
      }
    )
    booking = result.booking

    expect(booking.source).to eq("travel_agent")
    expect(booking.hotel_corporate_account_id).to eq(ta_a.id)
    expect(booking.corporate_booked_by_id).to eq(ta_a_user.id)
    expect(booking.corporate_booked_at).to be_present
    expect(booking.booking_rooms.first.rate_plan_id).to eq(fb_plan.id)
    expect(booking.agent_reference.length).to eq(100)
  end

  # C3/C4: payment deadline
  it "C3: TA-A (standard) gets a payment deadline" do
    result = book(plan: std_plan, adults: 2, nights: 1)

    expect(result.booking.payment_due_at).to be_present
  end

  it "C4: TA-B (direct bill) gets no payment deadline" do
    result = book(plan: corp_plan, adults: 2, nights: 1, relationship: ta_b, actor: ta_b_user)

    expect(result.booking.payment_due_at).to be_nil
  end

  # C5: 2 rooms, FB, 2A each, 3 nights
  it "C5: booking 2 rooms creates 2 bookings under one group, each priced at 1,350 (500 x 3 x 0.9)" do
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 3).to_s,
      adults: 2, children: 0, rooms: 2, rate_plan_id: fb_plan.id,
      rooms_detail: {
        "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } },
        "1" => { guests: { "0" => { name: "Ben Tan", phone: "+60123456780" } } }
      }
    }
    result = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user)

    expect(result).to be_success, Array(result.errors).to_sentence
    expect(result.bookings.size).to eq(2)
    expect(result.group_booking).to be_present
    result.bookings.each { |b| expect(b.total_amount.to_d).to eq(1_350.to_d) }
  end

  # C6: 2 rooms requested, second room's guests block has no lead name. The
  # agent asked for 2 rooms, so booking only the named one is refused rather
  # than quietly handing back fewer rooms than requested.
  it "C6: a requested room with no lead name refuses the whole request, naming the room" do
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 1).to_s,
      adults: 2, children: 0, rooms: 2, rate_plan_id: fb_plan.id,
      rooms_detail: {
        "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } },
        "1" => { guests: {} } # no lead guest at all
      }
    }
    result = nil
    expect {
      result = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user)
    }.not_to change(Booking, :count)

    expect(result).not_to be_success
    expect(result.errors).to eq([ "Name the lead guest for room 2." ])
  end

  # C7: a genuine mid-transaction failure (an unpriceable party - 5 adults
  # exceeds the Suite's 4-adult occupancy matrix) rolls back the whole request,
  # including the first room that would otherwise have succeeded.
  it "C7: a room that can't be priced rolls back the whole multi-room request (all-or-nothing)" do
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 1).to_s,
      adults: 5, children: 0, rooms: 2, rate_plan_id: std_plan.id,
      rooms_detail: {
        "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } },
        "1" => { guests: { "0" => { name: "Ben Tan", phone: "+60123456780" } } }
      }
    }
    expect {
      result = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user)
      expect(result).not_to be_success
    }.not_to change(Booking, :count)
  end

  # C9: no rate_plan_id, exactly one plan offered on the room type -> books it
  it "C9: with no rate_plan_id and only one plan offered on the category, books that plan" do
    solo_type = Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Solo Cabin", room_number_mode: "custom", quantity: 1, base_price: 150.0,
                    max_adults: 2, room_numbers: %w[S1] }
    )
    solo_std = solo_type.standard_rate_plan
    solo_std.update!(ta_access: "all")
    save_manual_prices!(solo_std, solo_type, { 1 => 150, 2 => 250 })
    # EnsureSystemPlans also dedicated a Corporate Rate to this category,
    # defaulting to ta_access "all" - hide it so STD really is the only plan
    # offered, matching the C9 scenario ("two offered -> refused" is covered
    # separately below).
    solo_type.rate_plans.find_by!(kind: "corporate").update!(ta_access: "hidden")

    params = {
      room_type_id: solo_type.id, check_in: check_in.to_s, check_out: (check_in + 1).to_s,
      adults: 1, children: 0, rooms: 1,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    result = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user)

    expect(result).to be_success, Array(result.errors).to_sentence
    expect(result.booking.booking_rooms.first.rate_plan_id).to eq(solo_std.id)
  end

  it "C9: with no rate_plan_id and two plans offered, is refused" do
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 1).to_s,
      adults: 2, children: 0, rooms: 1,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    result = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user)

    expect(result).not_to be_success
  end

  # C11: tourism tax not in the search quote, appears on the folio for a foreign lead
  it "C11: tourism tax is not part of the TA search quote (a note only) but appears on the folio for a foreign lead" do
    option = search_total(plan: std_plan, adults: 1, nights: 2)
    expect(option.tourism_tax_note).to be_present

    result = CorporatePortal::CreateAgentBooking.call(
      relationship: ta_a, user: ta_a_user,
      params: {
        room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 2).to_s,
        adults: 1, children: 0, rooms: 1, rate_plan_id: std_plan.id,
        rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789", country: "Singapore",
                                                     date_of_birth: "1990-01-01" } } } }
      }
    )
    booking = result.booking

    snapshot = Bookings::BuildFinancialSnapshot.new(
      hotel: hotel, booking: booking, room_type: suite, rate_plan: std_plan,
      check_in: booking.check_in, check_out: booking.check_out, guest_country: "Singapore", adults: 1
    ).call

    expect(snapshot.tax_lines.any? { |line| Booking.tourism_tax_line?(line) }).to be true
  end
end
