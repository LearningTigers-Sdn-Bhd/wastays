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

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(true)
    expect(booking.reload.status).to eq("no_show")
    expect(booking.booking_folio.folio_transactions.charge.where(category: "no_show_charge").sole.amount).to eq(100.0)
  end
end
