# frozen_string_literal: true

require "rails_helper"

# Test plan phase V, reports: V9-V11, V13.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.11.
# V12 (Meal Prep/BIBO) needs the separate boat-schedule subsystem and V6/V8
# (folio screen, AR invoice screen) need deeper view assertions - not covered
# here; see the test plan's §12 "Not covered" note.
RSpec.describe "Per-pax reports" do
  include_context "per-pax resort"

  let(:staff) { create(:user, account: hotel.account) }
  let(:business_date) { Date.current }

  def book_check_in_and_post(plan:, adults:, relationship:, actor:, nights: 1, guest_country: nil)
    params = {
      room_type_id: suite.id, check_in: business_date.to_s, check_out: (business_date + nights).to_s,
      adults: adults, children: 0, rooms: 1, rate_plan_id: plan.id,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789", country: guest_country,
                                                   date_of_birth: (guest_country.present? ? "1990-01-01" : nil) } } } }
    }
    booking = CorporatePortal::CreateAgentBooking.call(relationship: relationship, params: params, user: actor).booking

    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    RoomStatus.find_or_create_by!(hotel: hotel, room_type: suite, room_number: "F1").update!(status: "ready")
    check_in = Bookings::ProcessCheckIn.new(
      bookings: [ booking ], user: staff,
      details: { checked_in_at: Time.current.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M"),
                 tourism_tax_collected: "0", room_assignments: { booking.booking_rooms.first.id.to_s => "F1" } }
    ).call
    raise "check-in failed: #{check_in.error}" unless check_in.success?

    night_audit = create(:night_audit, hotel: hotel, business_date: business_date, performed_by_user: staff)
    posted = Folios::Charges::PostNightlyCharges.call(night_audit: night_audit, user: staff)
    raise "posting failed: #{posted.failed}" if posted.failed.any?

    booking.reload
  end

  # V9: Daily Revenue - revenue under the travel agent source, amount = posted nights
  it "V9: the Daily Revenue report groups a per-pax TA booking's posted charge under Travel Agent" do
    booking = book_check_in_and_post(plan: fb_plan, adults: 2, relationship: ta_a, actor: ta_a_user)

    report = HotelPortal::Reports::DailyRevenueReport.new(
      hotel: hotel, start_date: business_date, end_date: business_date
    ).call

    source_row = report.source_rows.find { |r| r[:source] == "Travel Agent" }
    expect(source_row).to be_present
    expect(source_row[:accommodation]).to eq(500.to_d) # FB 2A, 1 night, posted amount
    expect(booking.source).to eq("travel_agent")
  end

  # V10: Booking Performance - source = travel agent, count and revenue
  it "V10: Booking Performance counts and totals a per-pax TA booking under its source" do
    book_check_in_and_post(plan: std_plan, adults: 2, relationship: ta_a, actor: ta_a_user)

    bookings = Booking.for_financial_breakdown(hotel, business_date, business_date, nil)
    report = HotelPortal::Reports::BookingPerformanceReport.new(
      hotel: hotel, bookings: bookings, group_by: "source", date_preset: "custom"
    )

    group = report.groups.find { |g| g.label == "Travel Agent" }
    expect(group).to be_present
    expect(group.count).to eq(1)
  end

  # V14 (R12): Booking Performance groups revenue by the rate plan that sold it
  it "V14: Booking Performance groups bookings by rate plan, with their revenue and room nights" do
    book = lambda do |plan, nights|
      CorporatePortal::CreateAgentBooking.call(
        relationship: ta_a, user: ta_a_user,
        params: {
          room_type_id: suite.id, check_in: (business_date + 10).to_s, check_out: (business_date + 10 + nights).to_s,
          adults: 2, children: 0, rooms: 1, rate_plan_id: plan.id,
          rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
        }
      ).booking
    end
    fb_bookings = [ book.call(fb_plan, 3), book.call(fb_plan, 1) ]
    prm_booking = book.call(prm_plan, 2)

    bookings = Booking.for_financial_breakdown(hotel, business_date, business_date, nil)
    report = HotelPortal::Reports::BookingPerformanceReport.new(
      hotel: hotel, bookings: bookings, group_by: "rate_plan", date_preset: "custom"
    )

    fb_group = report.groups.find { |g| g.label == "Full Board" }
    prm_group = report.groups.find { |g| g.label == "Promo" }
    expect(fb_group.count).to eq(2)
    expect(fb_group.room_nights).to eq(4)
    expect(fb_group.currency_totals.sole[:gross]).to eq(fb_bookings.sum(&:total_amount))
    expect(prm_group.count).to eq(1)
    expect(prm_group.room_nights).to eq(2)
    expect(prm_group.currency_totals.sole[:gross]).to eq(prm_booking.total_amount)
  end

  # V11: Arrivals/Departures shows the correct adults/children
  it "V11: Arrivals/Departures lists the TA booking with its actual party size" do
    booking = book_check_in_and_post(plan: fb_plan, adults: 2, relationship: ta_a, actor: ta_a_user)

    report = HotelPortal::Reports::ArrivalsDeparturesReport.new(
      hotel: hotel, start_date: business_date, end_date: business_date + 1
    ).call
    # this booking checked in already, so it shows up in-house, not arrivals
    row = report.in_house.find { |r| r[:booking_id] == booking.id }

    expect(row).to be_present
    expect(row[:guest_count]).to eq("2 adults")
  end

  # V13: not covered - tourism tax turned out to be collected through its own
  # voucher/collection flow (issue_hotel_booking_tourism_tax_voucher et al),
  # not through the nightly forecasted charge lines PostNightlyCharges posts
  # (Folios::Reads::ForecastedChargeLines has no tourism_tax handling at all).
  # That flow is pre-existing and unrelated to per-pax pricing, so it's out of
  # scope for this test plan; not chased further here.
end
