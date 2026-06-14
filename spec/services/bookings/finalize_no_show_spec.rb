# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::FinalizeNoShow do
  it "posts the standard charge and finalizes a reviewed booking" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    room_type = create(:room_type, hotel: hotel)
    business_date = Date.current
    booking = create(
      :booking,
      hotel: hotel,
      status: "review_no_show",
      no_show_review_business_date: business_date,
      check_in: business_date,
      check_out: business_date + 2.days,
      tax_lines: []
    )
    create(:booking_room, booking: booking, room_type: room_type, subtotal: 200.0)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(true)
    expect(booking.reload.status).to eq("no_show")
    expect(booking.booking_folio.folio_transactions.charge.where(category: "no_show_charge").sole.amount).to eq(100.0)
  end

  it "links audit-generated no-show charges directly to the active night audit" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    business_date = hotel.current_business_date
    booking = create(
      :booking,
      hotel: hotel,
      status: "review_no_show",
      no_show_review_business_date: business_date,
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_lines: []
    )
    create(:booking_room, booking: booking, subtotal: 100.0)
    start_business_date_audit(hotel)
    audit = create(:night_audit, hotel: hotel, business_date: business_date, status: "running")

    result = described_class.call(booking: booking, user: user, night_audit: audit, automatic: true)

    expect(result.success?).to be(true)
    charge = booking.reload.booking_folio.folio_transactions.charge.sole
    expect(charge.night_audit).to eq(audit)
    expect(charge.metadata["night_audit_id"]).to eq(audit.id)
    expect(charge.metadata["posting_source"]).to eq("no_show")
  end

  it "blocks staff no-show finalization while night audit is running" do
    booking = create(:booking, status: "review_no_show", no_show_review_business_date: Date.current)
    start_business_date_audit(booking.hotel)

    result = described_class.call(booking: booking, user: create(:user))

    expect(result.success?).to be(false)
    expect(result.error).to eq(NightAudits::OperationalChangeGuard::ERROR_MESSAGE)
    expect(booking.reload.status).to eq("review_no_show")
  end
end
