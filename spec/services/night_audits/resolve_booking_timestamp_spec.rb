# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::ResolveBookingTimestamp do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel, :without_current_business_date) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", checked_in_at: nil, check_in: business_date, check_out: business_date + 1.day) }
  let(:audit) { create(:night_audit, hotel: hotel, business_date: business_date, status: "preparing", performed_by_user: nil) }

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    create(:booking_folio, hotel: hotel, booking: booking)
    allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel: hotel).and_return(true)
    allow(actor).to receive(:has_permission?).with("manage_bookings", hotel: hotel).and_return(true)
  end

  it "corrects a missing check-in timestamp with before/after evidence" do
    timestamp = Time.current.change(sec: 0)
    result = described_class.call(
      night_audit: audit,
      booking: booking,
      actor: actor,
      blocker_type: "checked_in_missing_timestamp",
      timestamp: timestamp,
      reason: "Verified registration card"
    )

    expect(result).to be_success
    expect(booking.reload.checked_in_at).to eq(timestamp)
    metadata = audit.night_audit_logs.find_by!(action_type: "blocker_resolved").metadata
    expect(metadata["before"]).to eq("checked_in_at" => nil)
    expect(metadata.dig("after", "checked_in_at")).to be_present
    expect(hotel.current_business_date_record).to be_open
  end

  it "requires the underlying booking-management permission" do
    allow(actor).to receive(:has_permission?).with("manage_bookings", hotel: hotel).and_return(false)

    result = described_class.call(
      night_audit: audit,
      booking: booking,
      actor: actor,
      blocker_type: "checked_in_missing_timestamp",
      timestamp: Time.current,
      reason: "Verified registration card"
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Manage bookings permission is required to correct booking timestamps.")
    expect(booking.reload.checked_in_at).to be_nil
  end
end
