# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::ResolveMissedArrival do
  let(:business_date) { Date.current - 1.day }
  let(:hotel) { create(:hotel, :without_current_business_date) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:booking) do
    create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 1.day)
  end
  let(:night_audit) do
    create(:night_audit,
      hotel: hotel,
      business_date: business_date,
      status: "preparing",
      performed_by_user: nil,
      blocked_details: { "missed_arrival_not_resolved" => [ { "booking_id" => booking.id } ] })
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    create(:booking_room, booking: booking, subtotal: 100.0)
    allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel: hotel).and_return(true)
    allow(actor).to receive(:has_permission?).with("manage_bookings", hotel: hotel).and_return(true)
  end

  it "marks a confirmed missed arrival as no-show and refreshes preparation" do
    result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "Guest did not arrive")

    expect(result).to be_success
    expect(booking.reload.status).to eq("no_show")
    expect(night_audit.reload.blocked_details["missed_arrival_not_resolved"]).to be_empty
    expect(hotel.current_business_date_record).to be_open
    expect(night_audit.night_audit_logs.find_by!(action_type: "blocker_resolved").metadata).to include(
      "before" => { "status" => "confirmed" },
      "after" => { "status" => "no_show" }
    )
  end

  it "requires a reason" do
    result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "")

    expect(result).not_to be_success
    expect(booking.reload.status).to eq("confirmed")
  end

  it "requires the underlying booking-management permission" do
    allow(actor).to receive(:has_permission?).with("manage_bookings", hotel: hotel).and_return(false)

    result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "Guest did not arrive")

    expect(result).not_to be_success
    expect(result.error).to eq("Manage bookings permission is required to resolve a missed arrival.")
    expect(booking.reload.status).to eq("confirmed")
  end
end
