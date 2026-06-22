# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::RecoverMissingFolio do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:night_audit) { create(:night_audit, hotel: hotel, business_date: business_date, status: "blocked", performed_by_user: actor) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 2.days,
      tax_lines: [ { "name" => "SST", "amount" => "20.00", "type" => "sst" } ])
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    start_business_date_audit(hotel)
    block_business_date_audit(hotel, blockers: { "missing_folio" => [ { "booking_id" => booking.id } ] })
    create(:booking_room, booking: booking, subtotal: 200.0)
  end

  it "creates a missing booking folio with the required invariants and forecasts" do
    result = described_class.call(
      booking: booking,
      hotel: hotel,
      actor: actor,
      night_audit: night_audit,
      reason: "Night audit blocker"
    )

    expect(result).to be_success
    expect(result).to be_created
    expect(result.folio).to have_attributes(
      hotel: hotel,
      booking: booking,
      status: "open",
      folio_number: 1
    )
    expect(result.folio.folio_forecasted_charges.forecast.count).to eq(4)
  end

  it "returns the existing folio without creating a duplicate" do
    existing_folio = create(:booking_folio, hotel: hotel, booking: booking, folio_number: 42)

    expect {
      result = described_class.call(
        booking: booking,
        hotel: hotel,
        actor: actor,
        night_audit: night_audit,
        reason: "Night audit blocker"
      )

      expect(result).to be_success
      expect(result).not_to be_created
      expect(result.folio).to eq(existing_folio)
    }.not_to change(BookingFolio, :count)
  end

  it "rejects a booking from another hotel" do
    other_booking = create(:booking)

    result = described_class.call(
      booking: other_booking,
      hotel: hotel,
      actor: actor,
      night_audit: night_audit,
      reason: "Night audit blocker"
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Booking does not belong to this hotel.")
  end

  it "does not sync payments or create folio transactions during recovery" do
    create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)

    expect {
      result = described_class.call(
        booking: booking,
        hotel: hotel,
        actor: actor,
        night_audit: night_audit,
        reason: "Night audit blocker"
      )

      expect(result).to be_success
    }.not_to change(FolioTransaction, :count)
  end

  it "records a financial audit event for the recovery" do
    result = described_class.call(
      booking: booking,
      hotel: hotel,
      actor: actor,
      night_audit: night_audit,
      reason: "Night audit blocker"
    )

    event = FinancialAuditEvent.find_by!(event_type: "missing_folio_recovered")
    expect(event).to have_attributes(
      hotel: hotel,
      booking: booking,
      booking_folio: result.folio,
      night_audit: night_audit,
      actor: actor,
      source: "audit_blocker_resolution",
      reason: "Night audit blocker"
    )
    expect(event.metadata).to include(
      "blocker_type" => "missing_folio",
      "booking_id" => booking.id,
      "booking_folio_id" => result.folio.id
    )
  end

  it "is idempotent when called repeatedly" do
    first = described_class.call(booking: booking, hotel: hotel, actor: actor, night_audit: night_audit, reason: "First")

    expect {
      second = described_class.call(booking: booking, hotel: hotel, actor: actor, night_audit: night_audit, reason: "Second")
      expect(second.folio).to eq(first.folio)
      expect(second).not_to be_created
    }.not_to change(BookingFolio, :count)
  end
end
