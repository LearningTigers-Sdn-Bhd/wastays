# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposit do
  it "records collected security deposits with GL mapping" do
    booking = create(:booking)
    folio = create(:booking_folio, booking: booking)

    deposit = create(:deposit, booking: booking, hotel: booking.hotel, booking_folio: folio, amount: 150)

    expect(deposit.hold_type).to eq("security")
    expect(deposit.status).to eq("collected")
    expect(deposit.gl_code).to eq("2030")
    expect(deposit.collected_at).to be_present
  end

  it "requires the folio to belong to the same booking" do
    booking = create(:booking)
    other_folio = create(:booking_folio)

    deposit = build(:deposit, booking: booking, hotel: booking.hotel, booking_folio: other_folio)

    expect(deposit).not_to be_valid
    expect(deposit.errors[:booking_folio]).to include("must belong to the same booking")
  end
end
