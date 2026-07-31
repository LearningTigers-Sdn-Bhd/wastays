# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ProcessLateCheckout do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 10) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", check_in: Date.current, check_out: Date.current + 1.day) }
  let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, room_number: "101") }
  let!(:folio) { Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: user) }

  before do
    booking.transition_status_to!("due_out_detected", event: "detect_due_out")
  end

  it "updates the checkout period, posts a charge, and resolves the booking" do
    new_check_out = Date.current + 2.days

    result = described_class.call(
      booking: booking,
      user: user,
      params: { resolution: "charge", amount: "150.00", check_out: new_check_out.to_s }
    )

    expect(result).to be_success
    expect(result).to be_charged
    expect(booking.reload.status).to eq("checked_in")
    expect(booking.check_out.to_date).to eq(new_check_out)
    expect(folio.folio_transactions.where(category: "late_checkout_charge").sum(:amount)).to eq(150.0)
  end

  it "updates the checkout period and resolves the booking without a charge" do
    new_check_out = Date.current + 2.days

    result = described_class.call(
      booking: booking,
      user: user,
      params: { resolution: "waive", check_out: new_check_out.to_s }
    )

    expect(result).to be_success
    expect(result).not_to be_charged
    expect(result).not_to be_rejected
    expect(booking.reload.status).to eq("checked_in")
    expect(booking.check_out.to_date).to eq(new_check_out)
    expect(folio.folio_transactions.where(category: "late_checkout_charge")).to be_empty
  end

  it "rejects late checkout and marks checkout required without posting a charge" do
    result = described_class.call(
      booking: booking,
      user: user,
      params: { resolution: "reject", check_out: (Date.current + 2.days).to_s }
    )

    expect(result).to be_success
    expect(result).not_to be_charged
    expect(result).to be_rejected
    expect(booking.reload.status).to eq("checkout_required")
    expect(booking.check_out.to_date).to eq(Date.current + 1.day)
    expect(folio.folio_transactions.where(category: "late_checkout_charge")).to be_empty
  end

  it "allows a later Night Audit to post normal charges after the stay is extended" do
    next_business_date = Date.current + 1.day
    described_class.call(
      booking: booking,
      user: user,
      params: { resolution: "charge", amount: "150.00", check_out: (Date.current + 2.days).to_s }
    )
    audit = create(:night_audit, hotel: hotel, business_date: next_business_date, status: "running", performed_by_user: user)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: next_business_date)
    start_business_date_audit(hotel)

    expect {
      Folios::Charges::PostNightlyCharges.call(night_audit: audit, user: user)
    }.to change { folio.folio_transactions.where(category: "accommodation").count }.by(1)

    expect(booking.reload.status).to eq("checked_in")
  end

  it "fails when the booking does not have a detected due-out" do
    booking.transition_status_to!("checked_in", event: "resolve_late_checkout")

    result = described_class.call(
      booking: booking,
      user: user,
      params: { resolution: "charge", amount: "150.00" }
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Booking does not have a detected due-out.")
    expect(folio.folio_transactions.where(category: "late_checkout_charge")).to be_empty
  end

  it "fails when staff requests a charge without a positive amount" do
    result = described_class.call(
      booking: booking,
      user: user,
      params: { resolution: "charge", amount: "0" }
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Charge amount must be greater than zero.")
    expect(booking.reload.status).to eq("due_out_detected")
    expect(folio.folio_transactions.where(category: "late_checkout_charge")).to be_empty
  end

  it "fails when a resolution is not selected" do
    result = described_class.call(booking: booking, user: user, params: {})

    expect(result).not_to be_success
    expect(result.error).to eq("Choose how to resolve this late checkout.")
    expect(booking.reload.status).to eq("due_out_detected")
  end
end
