# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ProcessLateCheckout do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 10) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", check_in: Date.current, check_out: Date.current + 1.day) }
  let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, quantity: 1, room_number: "101") }
  let!(:folio) { Folios::InitializeForBooking.call(booking: booking, user: user) }

  before do
    booking.transition_status_to!("review_due_out", event: "detect_late_checkout")
  end

  it "updates the checkout period, posts a charge, and resolves the booking" do
    new_check_out = Date.current + 2.days

    result = described_class.call(
      booking: booking,
      user: user,
      params: { charge_type: "charge", amount: "150.00", check_out: new_check_out.to_s }
    )

    expect(result).to be_success
    expect(result).to be_charged
    expect(booking.reload.status).to eq("checked_in")
    expect(booking.check_out.to_date).to eq(new_check_out)
    expect(folio.folio_transactions.where(category: "late_checkout_charge").sum(:amount)).to eq(150.0)
  end

  it "resolves without posting a charge" do
    result = described_class.call(
      booking: booking,
      user: user,
      params: { charge_type: "none", check_out: (Date.current + 2.days).to_s }
    )

    expect(result).to be_success
    expect(result).not_to be_charged
    expect(booking.reload.status).to eq("checked_in")
    expect(folio.folio_transactions.where(category: "late_checkout_charge")).to be_empty
  end

  it "fails when the booking is not pending late checkout review" do
    booking.transition_status_to!("checked_in", event: "resolve_late_checkout")

    result = described_class.call(
      booking: booking,
      user: user,
      params: { charge_type: "charge", amount: "150.00" }
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Booking is not pending late checkout review.")
    expect(folio.folio_transactions.where(category: "late_checkout_charge")).to be_empty
  end

  it "fails when staff requests a charge without a positive amount" do
    result = described_class.call(
      booking: booking,
      user: user,
      params: { charge_type: "charge", amount: "0" }
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Charge amount must be greater than zero.")
    expect(booking.reload.status).to eq("review_due_out")
    expect(folio.folio_transactions.where(category: "late_checkout_charge")).to be_empty
  end
end
