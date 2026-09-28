# frozen_string_literal: true

require "rails_helper"

# Test plan phase G: TA guest editing.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.10.
# The basics (edit before arrival, audit trail, blank ID keeps saved value,
# unchanged save) are already covered by spec/requests/corporate_portal/booking_guests_spec.rb.
# This adds G7, which is per-pax specific.
RSpec.describe "Per-pax TA guest editing" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  # G7 (RECORDED, R6): adding a named companion does not change `adults` or
  # re-price the booking - BookingGuests::Add never touches booking.adults,
  # and UpdateAgentBookingGuests never re-prices. A 1-adult booking with 3
  # companions added still shows the 1-adult price.
  it "G7 (R6): adding a companion via guest editing does not change adults or the price" do
    # adults: 2, but only the lead is named at booking time, leaving one
    # companion slot - UpdateAgentBookingGuests caps new rows at
    # (adults - existing guest rows), so this is the case where an addition is
    # actually accepted.
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 1).to_s,
      adults: 2, children: 0, rooms: 1, rate_plan_id: std_plan.id,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    booking = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user).booking
    expect(booking.total_amount.to_d).to eq(440.to_d) # 2-adult STD price
    expect(booking.booking_guests.count).to eq(1)

    result = CorporatePortal::UpdateAgentBookingGuests.call(
      booking: booking, user: ta_a_user,
      guests: { "new_1" => { name: "Ben Tan", phone: "+60123456780", country: "Malaysia" } }
    )

    expect(result.success?).to be(true), Array(result.errors).to_sentence
    expect(booking.booking_guests.count).to eq(2) # the companion was added as a guest record
    expect(booking.reload.adults).to eq(2) # RECORDED: R6 - unchanged, it was already 2
    expect(booking.reload.total_amount.to_d).to eq(440.to_d) # RECORDED: R6 - price untouched either way
  end
end
