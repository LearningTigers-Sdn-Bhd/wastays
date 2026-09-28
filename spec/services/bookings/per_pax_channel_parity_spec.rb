# frozen_string_literal: true

require "rails_helper"

# Test plan phase X: same stay, same price on every channel.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.7.
RSpec.describe "Per-pax price parity across channels" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  def ta_price(plan, adults:, children: 0, nights: 1)
    Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: check_in, check_out: check_in + nights,
      rate_plan: plan, adults: adults, children: children, child_ages: []
    ).call
  end

  def desk_price(plan, adults:, children: 0, nights: 1)
    Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: check_in, check_out: check_in + nights,
      rate_plan: plan, adults: adults, children: children, child_ages: []
    ).call
  end

  def public_price(plan, adults:, children: 0, child_ages: [], nights: 1)
    Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: check_in, check_out: check_in + nights,
      rate_plan: plan, adults: adults, children: children, child_ages: child_ages
    ).call
  end

  # X1: 2A, FB, 3 nights - identical everywhere, no children involved
  it "X1: 2 adults, FB, 3 nights is 1,350 on TA, desk and public alike" do
    expect(ta_price(fb_plan, adults: 2, nights: 3)).to eq(1_350.to_d)
    expect(desk_price(fb_plan, adults: 2, nights: 3)).to eq(1_350.to_d)
    expect(public_price(fb_plan, adults: 2, nights: 3)).to eq(1_350.to_d)
  end

  # X2: every channel carries the child's age to the price, so the same stay
  # costs the same wherever it was booked: 500 + 40% of the 1-adult 300 = 620
  # a night, 10% off every night at 3 nights = 1,674.
  it "X2: 2A + child 8, FB, 3 nights is 1,674 on TA, desk and public alike" do
    ta_booking = CorporatePortal::CreateAgentBooking.call(
      relationship: ta_a, user: ta_a_user,
      params: {
        room_type_id: suite.id, rate_plan_id: fb_plan.id, check_in: check_in.to_s, check_out: (check_in + 3).to_s,
        adults: 2, children: 1, child_ages: [ "8" ], rooms: 1,
        rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
      }
    ).booking
    desk_booking = Bookings::CreateManualBooking.new(
      hotel: hotel,
      params: {
        guest_name: "Ben Tan", guest_phone: "+60123456780", check_in: check_in, check_out: check_in + 3,
        room_type_id: suite.id, rate_plan_id: fb_plan.id, adults: 2, children: 1, child_ages: "8",
        require_room_number: false
      }
    ).call.booking

    expect(ta_booking.booking_rooms.sole.subtotal).to eq(1_674.to_d)
    expect(desk_booking.booking_rooms.sole.subtotal).to eq(1_674.to_d)
    expect(public_price(fb_plan, adults: 2, children: 1, child_ages: [ 8 ], nights: 3)).to eq(1_674.to_d)
    expect(ta_booking.child_ages).to eq([ 8 ])
    expect(desk_booking.child_ages).to eq([ 8 ])
  end

  it "X2b: without an age, every channel falls back to the plan's child multiplier alike (2,025)" do
    expect(ta_price(fb_plan, adults: 2, children: 1, nights: 3)).to eq(2_025.to_d)
    expect(desk_price(fb_plan, adults: 2, children: 1, nights: 3)).to eq(2_025.to_d)
    expect(public_price(fb_plan, adults: 2, children: 1, nights: 3)).to eq(2_025.to_d)
  end

  # X3: 4A, PRM, 5 nights - PRM has no long-stay rules, identical everywhere
  it "X3: 4 adults, PRM, 5 nights is identical on every channel (no long-stay rules on PRM)" do
    expect(ta_price(prm_plan, adults: 4, nights: 5)).to eq(3_900.to_d)
    expect(desk_price(prm_plan, adults: 4, nights: 5)).to eq(3_900.to_d)
    expect(public_price(prm_plan, adults: 4, nights: 5)).to eq(3_900.to_d)
  end

  # X4: STD via OTA gets no long-stay discount (STD has none anyway; use FB to
  # actually exercise the OTA exclusion, since only FB carries discount rules).
  it "X4: an OTA booking on a discount-bearing plan is not discounted, unlike the same stay direct" do
    direct = Bookings::BuildFinancialSnapshot.new(
      hotel: hotel, booking: nil, room_type: suite, rate_plan: fb_plan,
      check_in: check_in, check_out: check_in + 5, guest_country: "Malaysia", adults: 2
    ).call

    ota_booking = create(:booking, hotel: hotel, source: "ota")
    ota = Bookings::BuildFinancialSnapshot.new(
      hotel: hotel, booking: ota_booking, room_type: suite, rate_plan: fb_plan,
      check_in: check_in, check_out: check_in + 5, guest_country: "Malaysia", adults: 2
    ).call

    expect(direct.room_total).to eq(2_340.to_d) # discounted (see B1)
    expect(ota.room_total).to eq(2_500.to_d) # 500 x 5, undiscounted
  end

  # X5: a booking keeps its children's ages on the room's occupancy snapshot,
  # so extending the stay re-prices the child at the same age band.
  it "X5: extending a stay priced with a child's age keeps the age band" do
    original_snapshot = Bookings::BuildFinancialSnapshot.new(
      hotel: hotel, booking: nil, room_type: suite, rate_plan: fb_plan,
      check_in: check_in, check_out: check_in + 3, guest_country: "Malaysia",
      adults: 2, children: 1, child_ages: [ 8 ]
    ).call
    expect(original_snapshot.room_total).to eq(1_674.to_d)

    booking = create(:booking, hotel: hotel, source: "direct", status: "confirmed",
                                check_in: check_in, check_out: check_in + 3, adults: 2, children: 1,
                                total_amount: original_snapshot.room_total)
    booking.booking_rooms.create!(
      room_type: suite, rate_plan: fb_plan, subtotal: original_snapshot.room_total,
      nightly_rate_snapshot: original_snapshot.nightly_rate_snapshot,
      occupancy_snapshot: { "adults" => 2, "children" => 1, "child_ages" => [ 8 ] }
    )

    result = Bookings::UpdateStayService.new(
      booking: booking, params: { check_out: (check_in + 4).to_s }
    ).call
    expect(result.success?).to be(true), Array(result.errors).to_sentence

    # 4 nights x 620 x 0.9 = 2,232
    expect(result.booking.reload.booking_rooms.sole.subtotal).to eq(2_232.to_d)
  end
end
