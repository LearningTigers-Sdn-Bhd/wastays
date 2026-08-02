# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::ResolveMissingFolio do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:night_audit) do
    create(:night_audit,
      hotel: hotel,
      business_date: business_date,
      status: "blocked",
      performed_by_user: actor,
      blocked_details: { "missing_folio" => [ { "booking_id" => booking.id } ] })
  end
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day,
      checked_in_at: Time.current)
  end

  before do
    allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel: hotel).and_return(true)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    start_business_date_audit(hotel)
    block_business_date_audit(hotel, blockers: { "missing_folio" => [ { "booking_id" => booking.id } ] })
    create(:booking_room, booking: booking, subtotal: 100.0)
  end

  it "recovers the folio for a current audit-blocked missing folio blocker" do
    result = described_class.call(
      night_audit: night_audit,
      booking: booking,
      actor: actor,
      reason: "Resolve blocker"
    )

    expect(result).to be_success
    expect(result.folio).to eq(booking.reload.booking_folio)
    expect(night_audit.reload.blocked_details["missing_folio"]).to be_empty
    expect(hotel.current_business_date_record).to be_audit_blocked
    expect(NightAuditLog.find_by!(action_type: "blocker_resolved").metadata).to include(
      "blocker_type" => "missing_folio",
      "booking_id" => booking.id
    )
  end

  it "leaves missing nightly charges visible after recovery" do
    result = described_class.call(
      night_audit: night_audit,
      booking: booking,
      actor: actor,
      reason: "Resolve blocker"
    )

    expect(result).to be_missing_nightly_charges_remaining
    expect(result.message).to eq("Folio recovered. Missing nightly charges are still detected.")
    expect(night_audit.reload.blocked_details["missing_nightly_charges"].sole["booking_id"]).to eq(booking.id)
  end

  it "rolls back the recovery when the business-date snapshot cannot be refreshed" do
    allow(NightAudits::Resolutions::RefreshSnapshot).to receive(:call!).and_raise("Could not refresh blocker snapshot")

    expect {
      @result = described_class.call(
        night_audit: night_audit,
        booking: booking,
        actor: actor,
        reason: "Resolve blocker"
      )
    }.not_to change(BookingFolio, :count)

    expect(@result).not_to be_success
    expect(@result.error).to eq("Could not refresh blocker snapshot")
    expect(booking.reload.booking_folio).to be_nil
    expect(night_audit.reload.blocked_details["missing_folio"]).to contain_exactly(include("booking_id" => booking.id))
    expect(FinancialAuditEvent.where(event_type: "missing_folio_recovered", booking_id: booking.id)).not_to exist
    expect(NightAuditLog.where(night_audit: night_audit, action_type: "blocker_resolved")).not_to exist
  end

  it "rejects open business dates" do
    hotel.current_business_date_record.update!(status: "open")

    result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "Resolve blocker")

    expect(result).not_to be_success
    expect(result.error).to eq("Business date must be audit blocked before resolving blockers.")
  end

  it "rejects audit-running business dates" do
    hotel.current_business_date_record.update!(status: "audit_running")

    result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "Resolve blocker")

    expect(result).not_to be_success
    expect(result.error).to eq("Business date must be audit blocked before resolving blockers.")
  end

  it "rejects closed business dates" do
    hotel.current_business_date_record.update!(status: "closed")

    result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "Resolve blocker")

    expect(result).not_to be_success
    expect(result.error).to eq("Hotel has no current accounting business date.")
  end

  it "rejects force-closed business dates" do
    hotel.current_business_date_record.update!(status: "force_closed")

    result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "Resolve blocker")

    expect(result).not_to be_success
    expect(result.error).to eq("Hotel has no current accounting business date.")
  end

  it "rejects bookings that are not in the missing folio blocker set" do
    other_booking = create(:booking, hotel: hotel, status: "checked_in", check_in: business_date, check_out: business_date + 1.day)
    create(:booking_folio, hotel: hotel, booking: other_booking)

    result = described_class.call(night_audit: night_audit, booking: other_booking, actor: actor, reason: "Resolve blocker")

    expect(result).not_to be_success
    expect(result.error).to eq("Booking is not in the missing folio blocker list.")
  end

  it "rejects unauthorized actors" do
    allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel: hotel).and_return(false)

    result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "Resolve blocker")

    expect(result).not_to be_success
    expect(result.error).to eq("You do not have permission to resolve Night Audit blockers.")
  end
end
