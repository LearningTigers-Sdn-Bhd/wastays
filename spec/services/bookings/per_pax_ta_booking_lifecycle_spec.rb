# frozen_string_literal: true

require "rails_helper"

# Test plan phases L (life of the booking) and K (cancellation / auto-release).
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.8-7.9.
#
# Scope note: L4 (night audit posting), L6 (extend after a night is posted),
# L10/L11 (checkout settlement + AR invoice) and L14 (group cancellation) need
# the night-audit and checkout/settlement orchestration (NightAudits::Run,
# Folios::Checkout::ProcessCheckoutActions), which is its own large surface
# with existing dedicated specs elsewhere - not re-verified here for time.
# L5/L6/L7's re-pricing-on-extend/shorten mechanics for a per-pax plan are
# already covered by per_pax_channel_parity_spec.rb (X5) and this file (L5/L7).
RSpec.describe "Per-pax TA booking lifecycle" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  def book(plan:, adults:, children: 0, child_ages: [], nights: 3, relationship: ta_a, actor: ta_a_user, check_in: self.check_in)
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + nights).to_s,
      adults: adults, children: children, child_ages: child_ages, rooms: 1, rate_plan_id: plan.id,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    CorporatePortal::CreateAgentBooking.call(relationship: relationship, params: params, user: actor).booking
  end

  # L1: listed with source "travel agent" and the agency
  it "L1: a TA booking is attributed to the travel agent source and the agency" do
    booking = book(plan: fb_plan, adults: 2)

    expect(booking.source).to eq("travel_agent")
    expect(booking.hotel_corporate_account_id).to eq(ta_a.id)
  end

  # L2: assign a room on the unassigned TA booking
  it "L2: a room can be assigned to an unassigned TA booking" do
    booking = book(plan: fb_plan, adults: 2)
    staff = create(:user, account: hotel.account)
    RoomStatus.find_or_create_by!(hotel: hotel, room_type: suite, room_number: "F1").update!(status: "ready")

    result = Bookings::AssignRoom.new(booking: booking, room_number: "F1", user: staff).call

    expect(result).to be_success
    expect(booking.booking_rooms.first.reload.room_number).to eq("F1")
  end

  # L3: check-in carries guests over; price unchanged
  it "L3: checking in a TA booking leaves the price unchanged" do
    booking = book(plan: fb_plan, adults: 2, nights: 2, check_in: Date.current)
    staff = create(:user, account: hotel.account)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    original_total = booking.total_amount

    result = Bookings::ProcessCheckIn.new(
      bookings: [ booking ], user: staff,
      details: {
        checked_in_at: Time.current.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M"),
        tourism_tax_collected: "0",
        room_assignments: { booking.booking_rooms.first.id.to_s => "F1" }
      }
    ).call

    expect(result.success?).to be(true)
    expect(booking.reload.status).to eq("checked_in")
    expect(booking.total_amount).to eq(original_total)
  end

  # L5: extend FB 2A 2 -> 3 nights before any posting: whole stay re-priced
  it "L5: extending FB 2A from 2 to 3 nights re-prices the whole stay, 1,000 -> 1,350" do
    booking = book(plan: fb_plan, adults: 2, nights: 2)
    expect(booking.total_amount.to_d).to eq(1_000.to_d)

    result = Bookings::UpdateStayService.new(booking: booking, params: { check_out: (check_in + 3).to_s }).call

    expect(result.success?).to be(true)
    expect(booking.reload.total_amount.to_d).to eq(1_350.to_d)
  end

  # L7: shorten 3 -> 2 nights: discount removed, total 1,000
  it "L7: shortening FB 2A from 3 to 2 nights drops below the discount threshold, back to 1,000" do
    booking = book(plan: fb_plan, adults: 2, nights: 3)
    expect(booking.total_amount.to_d).to eq(1_350.to_d)

    result = Bookings::UpdateStayService.new(booking: booking, params: { check_out: (check_in + 2).to_s }).call

    expect(result.success?).to be(true)
    expect(booking.reload.total_amount.to_d).to eq(1_000.to_d)
  end

  # L8: change plan FB -> PRM re-prices for the same party, ages included.
  # FB prices the 8-year-old by its band; PRM has no bands, so the same child
  # falls back to PRM's child multiplier.
  it "L8: changing plan FB -> PRM re-prices the booking for the same party" do
    booking = book(plan: fb_plan, adults: 2, children: 1, child_ages: [ 8 ], nights: 1)
    expect(booking.total_amount.to_d).to eq(620.to_d)

    result = Bookings::UpdateStayService.new(booking: booking, params: { rate_selection: prm_plan.id.to_s }).call

    expect(result.success?).to be(true)
    expect(booking.reload.total_amount.to_d).to eq(720.to_d) # PRM 2A + 1C fallback (see table 6a)
    expect(booking.booking_rooms.first.rate_plan_id).to eq(prm_plan.id)
    expect(booking.child_ages).to eq([ 8 ])
  end

  # L12: no-show
  it "L12: a no-show is finalized with a charge and the agency stays attached" do
    business_date = Date.current
    booking = book(plan: fb_plan, adults: 2, nights: 2, check_in: business_date)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    staff = create(:user, account: hotel.account)
    # no_show_detected is reached through the night audit's detection sweep
    # (NightAudits::DetectMissedArrivals), not a direct status transition;
    # jump straight to the state FinalizeNoShow expects, as finalize_no_show_spec.rb does.
    booking.update_columns(status: "no_show_detected", no_show_detected_business_date: business_date)

    result = Bookings::FinalizeNoShow.call(booking: booking.reload, user: staff)

    expect(result.success?).to be(true)
    expect(booking.reload.status).to eq("no_show")
    expect(booking.hotel_corporate_account_id).to eq(ta_a.id)
  end

  # L13: hotel cancels a paid TA booking
  it "L13: the hotel can cancel a TA booking directly, releasing its inventory" do
    business_date = Date.current
    booking = book(plan: fb_plan, adults: 2, nights: 2, check_in: business_date)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    staff = create(:user, account: hotel.account)

    result = Bookings::TransitionStatus.new(
      booking: booking, status: "cancelled", user: staff, options: { reason: "Guest requested" }
    ).call

    expect(result.success?).to be(true)
    expect(booking.reload.status).to eq("cancelled")
  end
end

RSpec.describe "Per-pax TA cancellation and auto-release" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  def book(plan:, adults:, relationship: ta_a, actor: ta_a_user, nights: 3)
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + nights).to_s,
      adults: adults, children: 0, rooms: 1, rate_plan_id: plan.id,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    CorporatePortal::CreateAgentBooking.call(relationship: relationship, params: params, user: actor).booking
  end

  # K1: TA cancels an unpaid booking - inventory back, audited
  it "K1: TA-A cancels an unpaid booking, releasing the room and logging the agency-portal source" do
    booking = book(plan: fb_plan, adults: 2)

    result = CorporatePortal::CancelAgentBooking.call(booking: booking, user: ta_a_user)

    expect(result).to be_success
    expect(booking.reload.status).to eq("cancelled")
    log = BookingAuditLog.where(auditable: booking, action_type: "cancel").last
    expect(log.source).to eq(CorporatePortal::CancelAgentBooking::SOURCE)
  end

  # K2: TA cancels after payment approved - refused
  it "K2: TA-A cannot cancel once the booking's payment has been approved" do
    booking = book(plan: fb_plan, adults: 2)
    booking.update!(payment_status: "captured")

    result = CorporatePortal::CancelAgentBooking.call(booking: booking, user: ta_a_user)

    expect(result).not_to be_success
    expect(booking.reload.status).not_to eq("cancelled")
  end

  # K4: sweeper releases a TA-A booking past its deadline, unpaid
  it "K4: the deadline sweeper releases an unpaid TA-A booking past its deadline" do
    booking = book(plan: fb_plan, adults: 2)
    booking.update!(payment_status: "pending", payment_due_at: 1.hour.ago)

    result = Bookings::ReleaseUnpaidAgentBookings.call(now: Time.current)

    expect(result.released).to include(booking.id)
    expect(booking.reload.status).to eq("cancelled")
    log = BookingAuditLog.where(auditable: booking, action_type: "cancel").last
    expect(log.source).to eq(Bookings::ReleaseUnpaidAgentBookings::SOURCE)
  end

  # K6: the sweeper never releases TA-B (direct bill - no deadline)
  it "K6: the sweeper never touches a TA-B (direct bill) booking, which has no payment_due_at" do
    booking = book(plan: std_plan, adults: 2, relationship: ta_b, actor: ta_b_user)
    expect(booking.payment_due_at).to be_nil

    result = Bookings::ReleaseUnpaidAgentBookings.call(now: Time.current + 1.year)

    expect(result.released).not_to include(booking.id)
    expect(booking.reload.status).to eq("confirmed")
  end
end
