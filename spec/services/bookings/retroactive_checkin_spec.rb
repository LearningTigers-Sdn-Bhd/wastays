# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Retroactive Check-in", type: :service do
  let(:hotel) { create(:hotel) }
  let(:past_date) { 1.day.ago.to_date }
  let(:booking) { create(:booking, hotel: hotel, status: "confirmed", total_amount: 250.0, check_in: past_date, check_out: past_date + 1.day) }
  let(:user) { create(:user) }
  let(:timestamp) { past_date.to_time + 14.hours } # 2 PM yesterday

  before do
    create(:booking_room, booking: booking, subtotal: 200.0)
    booking.update(tax_lines: [ { "name" => "SST", "amount" => "12.00" } ])
    create(:night_audit, hotel: hotel, business_date: past_date, status: "completed")
  end

  it "blocks check-in on a closed date without override" do
    result = Bookings::TransitionStatus.new(
      booking: booking,
      status: "checked_in",
      timestamp: timestamp,
      user: user
    ).call

    expect(result.success?).to be false
    expect(result.error).to include("Reason required for backdated check-in")
  end

  it "allows check-in on a closed date with override and posts charges" do
    result = Bookings::TransitionStatus.new(
      booking: booking,
      status: "checked_in",
      timestamp: timestamp,
      user: user,
      options: { override_night_audit: true, reason: "Manual reservation missed" }
    ).call

    expect(result.success?).to be true
    expect(booking.reload.status).to eq("checked_in")
    expect(booking.checked_in_at.to_date).to eq(past_date)

    folio = booking.booking_folio
    expect(folio).to be_present
    expect(folio.folio_transactions.count).to be >= 2 # Room charge + SST
    expect(folio.outstanding_balance).to eq(212.0) # 200 + 12

    log = BookingAuditLog.last
    expect(log.metadata["retroactive_checkin"]).to be true
    expect(log.metadata["retroactive_reason"]).to eq("Manual reservation missed")
  end

  it "syncs existing captured payments during check-in" do
    create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10000, captured_at: Time.current) # 100.0

    result = Bookings::TransitionStatus.new(
      booking: booking,
      status: "checked_in",
      timestamp: timestamp,
      user: user,
      options: { override_night_audit: true, reason: "Correction" }
    ).call

    expect(result.success?).to be(true), "Expected success but got error: #{result.error}"
    folio = booking.booking_folio
    expect(folio.folio_transactions.payment.count).to eq(1)
    expect(folio.folio_transactions.payment.first.user).to be_nil
    expect(folio.outstanding_balance).to eq(112.0) # 212 - 100
  end
end
