# frozen_string_literal: true

require "rails_helper"

# Test plan phases L (continued: L4, L6, L9, L10, L11, L14) and K (continued:
# K3, K5, K7) - the night-audit / checkout orchestration this session's first
# pass (per_pax_ta_booking_lifecycle_spec.rb) deferred.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.8-7.9.
RSpec.describe "Per-pax night audit and checkout" do
  include_context "per-pax resort"

  let(:staff) do
    user = create(:user, account: hotel.account)
    role = create(:role, account: hotel.account)
    %w[view_bookings manage_bookings post_charges post_folio_charges post_folio_payments manage_night_audit].each do |slug|
      role.permissions << (Permission.find_by(slug: slug) || create(:permission, slug: slug))
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    user
  end

  def book(plan:, adults:, children: 0, nights: 3, relationship: ta_a, actor: ta_a_user, check_in:)
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + nights).to_s,
      adults: adults, children: children, rooms: 1, rate_plan_id: plan.id,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    CorporatePortal::CreateAgentBooking.call(relationship: relationship, params: params, user: actor).booking
  end

  def check_in!(booking, room_number: "F1")
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: booking.check_in.to_date)
    RoomStatus.find_or_create_by!(hotel: hotel, room_type: suite, room_number: room_number).update!(status: "ready")
    result = Bookings::ProcessCheckIn.new(
      bookings: [ booking ], user: staff,
      details: {
        checked_in_at: Time.current.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M"),
        tourism_tax_collected: "0",
        room_assignments: { booking.booking_rooms.first.id.to_s => room_number }
      }
    ).call
    raise "check-in failed: #{result.error}" unless result.success?

    booking.reload
  end

  # Posts one night's forecasted charges as the night audit would, without
  # running the full NightAudits::Run orchestration (business-date rollover,
  # journal batches, pre-close evaluation) which is out of scope here.
  def post_night!(date)
    night_audit = create(:night_audit, hotel: hotel, business_date: date, performed_by_user: staff)
    result = Folios::Charges::PostNightlyCharges.call(night_audit: night_audit, user: staff)
    raise "posting #{date} failed: #{result.failed}" if result.failed.any?

    night_audit
  end

  def post_every_night!(booking)
    (booking.check_in.to_date...booking.check_out.to_date).each { |date| post_night!(date) }
  end

  # L4: night audit posts each night at the snapshot's price
  it "L4: night audit posts each night's charge at the nightly_rate_snapshot amount" do
    business_date = Date.current
    booking = check_in!(book(plan: fb_plan, adults: 2, nights: 3, check_in: business_date))
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    snapshot = booking.booking_rooms.first.nightly_rate_snapshot

    night_audit = post_night!(business_date)

    posted = booking.booking_folio.folio_transactions.charge.where(category: "accommodation").sole
    expect(posted.amount.to_d).to eq(snapshot.fetch(business_date.iso8601).fetch("price").to_d)
    expect(posted.night_audit_id).to eq(night_audit.id)
  end

  # L6 (RECORDED): the posted folio charge for an already-posted night is
  # frozen (SyncForecastedCharges never recreates a posted night), but the
  # booking_room's nightly_rate_snapshot is fully REBUILT by the extension,
  # including night 1 - which now qualifies for the >=3-night 10% discount
  # (from_night: 1, i.e. every night). So the snapshot and the actual posted
  # charge diverge for night 1: the folio shows 500 charged, the (would-be
  # current) snapshot says 450. This is exactly the manual-reconciliation gap
  # the handoff doc's "Open decision #5" already flagged and decided not to
  # automate - confirmed here at the data level, not just by reading the code.
  it "L6 (RECORDED): extending past a posted night leaves the folio charge frozen but rebuilds the snapshot underneath it" do
    business_date = Date.current
    booking = check_in!(book(plan: fb_plan, adults: 2, nights: 2, check_in: business_date))
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    post_night!(business_date) # posts night 1 at the un-discounted 2-night rate (500)

    result = Bookings::UpdateStayService.new(
      booking: booking, params: { check_out: (business_date + 3).to_s }
    ).call
    expect(result.success?).to be(true)

    snapshot = booking.reload.booking_rooms.first.nightly_rate_snapshot
    night1 = snapshot.fetch(business_date.iso8601)
    night2 = snapshot.fetch((business_date + 1).iso8601)
    night3 = snapshot.fetch((business_date + 2).iso8601)

    posted = booking.booking_folio.folio_transactions.charge.where(category: "accommodation").sole
    expect(posted.amount.to_d).to eq(500.to_d) # RECORDED: the posted charge is untouched
    expect(night1["price"].to_d).to eq(450.to_d) # RECORDED: but the snapshot rebuilds night 1 too, at the new discount
    expect(night2["price"].to_d).to eq(450.to_d)
    expect(night3["price"].to_d).to eq(450.to_d)
  end

  # L9: early checkout charges every unused night at its booked (already
  # discounted) rate - the "strict/non-refundable" policy from the handoff doc.
  it "L9: an early checkout on night 2 of an FB 2A 3-night stay charges the unused night at its discounted rate" do
    business_date = Date.current
    booking = check_in!(book(plan: fb_plan, adults: 2, nights: 3, check_in: business_date))
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    snapshot = booking.booking_rooms.first.nightly_rate_snapshot
    unused_night_price = snapshot.fetch((business_date + 2).iso8601).fetch("price").to_d
    expect(unused_night_price).to eq(450.to_d) # discounted (10% of 500)

    post_night!(business_date)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date + 1)
    post_night!(business_date + 1)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date + 2)

    result = Bookings::ProcessEarlyDeparture.call(
      booking: booking, user: staff, params: { apply_charge: "false" },
      options: { timestamp: (business_date + 2).in_time_zone(hotel.hotel_time_zone).noon, defer_checkout: true }
    )
    expect(result.success?).to be(true), result.error.to_s

    booking.reload
    expect(booking.check_out.to_date).to eq(business_date + 2)
    early_charge = booking.booking_folio.folio_transactions.charge
      .where(category: "early_departure_charge").sum(:amount)
    expect(early_charge.to_d).to eq(unused_night_price)
  end

  # L10: direct-bill checkout goes to AR, not the guest's own payment
  it "L10: checking out a direct-bill (TA-B) stay creates an AR invoice for the discounted total, no payment required" do
    business_date = Date.current
    booking = check_in!(book(plan: std_plan, adults: 2, nights: 1, check_in: business_date, relationship: ta_b, actor: ta_b_user))
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    post_night!(business_date)
    checkout_date = business_date + 1
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: checkout_date)
    folio = booking.reload.booking_folio

    result = Checkouts::ProcessBookingCheckout.call(
      booking: booking, hotel: hotel, user: staff, timestamp: checkout_date.in_time_zone(hotel.hotel_time_zone).noon,
      folio_action_params: { folio.id.to_s => { action: "direct_bill" } }, posting_date: checkout_date
    )
    expect(result.success?).to be(true), result.error.to_s

    invoice = Receivable.find_by(booking_folio: folio)
    expect(invoice).to be_present
    expect(invoice.hotel_corporate_account_id).to eq(ta_b.id)
    expect(invoice.amount.to_d).to eq(440.to_d) # 2A STD, 1 night
    expect(booking.reload.status).to eq("completed")
  end

  # L11: a standard (TA-A) stay settles at checkout, no AR invoice
  it "L11: checking out a standard (TA-A) stay with the balance already paid creates no AR invoice" do
    business_date = Date.current
    booking = check_in!(book(plan: std_plan, adults: 2, nights: 1, check_in: business_date))
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    post_night!(business_date)
    checkout_date = business_date + 1
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: checkout_date)
    folio = booking.reload.booking_folio
    balance = folio.reload.outstanding_balance
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash",
                                amount: balance, posting_date: checkout_date)

    result = Checkouts::ProcessBookingCheckout.call(
      booking: booking, hotel: hotel, user: staff, timestamp: checkout_date.in_time_zone(hotel.hotel_time_zone).noon,
      folio_action_params: { folio.id.to_s => { action: "close" } }, posting_date: checkout_date
    )
    expect(result.success?).to be(true), result.error.to_s

    expect(Receivable.where(booking_folio: folio)).to be_none
    expect(booking.reload.status).to eq("completed")
  end

  # L14 (RECORDED): desk cancels one room of a TA group
  it "L14: desk-cancelling one room of a TA group leaves the other room untouched (RECORDED)" do
    params = {
      room_type_id: suite.id, check_in: (Date.current + 20).to_s, check_out: (Date.current + 22).to_s,
      adults: 2, children: 0, rooms: 2, rate_plan_id: fb_plan.id,
      rooms_detail: {
        "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } },
        "1" => { guests: { "0" => { name: "Ben Tan", phone: "+60123456780" } } }
      }
    }
    result = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user)
    room_a, room_b = result.bookings
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)

    cancel = Bookings::TransitionStatus.new(booking: room_a, status: "cancelled", user: staff).call

    expect(cancel.success?).to be(true)
    expect(room_a.reload.status).to eq("cancelled")
    expect(room_b.reload.status).to eq("confirmed") # RECORDED: the group survives a partial desk cancellation
    expect(room_b.group_booking_id).to eq(room_a.group_booking_id) # still grouped together
  end
end

RSpec.describe "Per-pax cancellation and auto-release (continued)" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  def group_book(plan:, relationship: ta_a, actor: ta_a_user)
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 3).to_s,
      adults: 2, children: 0, rooms: 2, rate_plan_id: plan.id,
      rooms_detail: {
        "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } },
        "1" => { guests: { "0" => { name: "Ben Tan", phone: "+60123456780" } } }
      }
    }
    CorporatePortal::CreateAgentBooking.call(relationship: relationship, params: params, user: actor)
  end

  # K3: TA cancels one room of a group - the whole group cancels
  it "K3: cancelling one room of a TA group through the portal cancels the whole group" do
    result = group_book(plan: fb_plan)
    room_a, room_b = result.bookings

    cancel_result = CorporatePortal::CancelAgentBooking.call(booking: room_a, user: ta_a_user)

    expect(cancel_result).to be_success
    expect(room_a.reload.status).to eq("cancelled")
    expect(room_b.reload.status).to eq("cancelled")
  end

  # K5: sweeper - a pending payment slip protects the booking from release
  it "K5: the sweeper does not release a booking with a payment slip pending review" do
    result = group_book(plan: fb_plan)
    booking = result.bookings.first
    booking.update!(payment_status: "pending", payment_due_at: 1.hour.ago)
    create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: ta_a, booking: booking, status: "pending", auto_invoice: nil)

    sweep = Bookings::ReleaseUnpaidAgentBookings.call(now: Time.current)

    expect(sweep.released).not_to include(booking.id)
    expect(booking.reload.status).not_to eq("cancelled")
  end

  # K7: the sweeper releases every room of a group together
  it "K7: the sweeper releases every room of a group whose deadline has passed" do
    result = group_book(plan: fb_plan)
    result.bookings.each { |b| b.update!(payment_status: "pending", payment_due_at: 1.hour.ago) }

    sweep = Bookings::ReleaseUnpaidAgentBookings.call(now: Time.current)

    expect(sweep.released).to match_array(result.bookings.map(&:id))
    result.bookings.each { |b| expect(b.reload.status).to eq("cancelled") }
  end
end
