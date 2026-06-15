# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::ReviewDueOuts do
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur") }
  let(:user) { create(:user, account: hotel.account) }
  let(:business_date) { Date.new(2026, 6, 12) }
  let(:night_audit) { create(:night_audit, hotel: hotel, business_date: business_date, status: "running", performed_by_user: user) }

  it "moves checked-in bookings due on or before the business date to review_due_out" do
    due_today = create(:booking, hotel: hotel, status: "checked_in", check_out: business_date, checked_in_at: 1.day.ago)
    overdue = create(:booking, hotel: hotel, status: "checked_in", check_out: business_date - 1.day, checked_in_at: 2.days.ago)

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.changed.pluck("booking_id")).to contain_exactly(due_today.id, overdue.id)
    expect(due_today.reload.status).to eq("review_due_out")
    expect(overdue.reload.status).to eq("review_due_out")
  end

  it "leaves future, non-checked-in, and already reviewed bookings unchanged" do
    future = create(:booking, hotel: hotel, status: "checked_in", check_out: business_date + 1.day, checked_in_at: 1.day.ago)
    confirmed = create(:booking, hotel: hotel, status: "confirmed", check_out: business_date)
    reviewed = create(:booking, hotel: hotel, status: "review_due_out", check_out: business_date, checked_in_at: 1.day.ago)

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.changed).to be_empty
    expect(future.reload.status).to eq("checked_in")
    expect(confirmed.reload.status).to eq("confirmed")
    expect(reviewed.reload.status).to eq("review_due_out")
  end

  it "records an immutable booking audit log linked to the night audit and business date" do
    booking = create(:booking, hotel: hotel, status: "checked_in", check_out: business_date, checked_in_at: 1.day.ago)

    described_class.call(night_audit: night_audit, user: user)

    log = BookingAuditLog.where(auditable: booking, action_type: "status_change").sole
    expect(log.source).to eq("night_audit")
    expect(log.old_value).to eq("status" => "checked_in")
    expect(log.new_value).to eq("status" => "review_due_out")
    expect(log.metadata).to include(
      "night_audit_id" => night_audit.id,
      "business_date" => business_date.iso8601,
      "event" => "detect_late_checkout"
    )
  end

  it "returns transition failures without changing the booking" do
    booking = create(:booking, hotel: hotel, status: "checked_in", check_out: business_date, checked_in_at: 1.day.ago)
    allow_any_instance_of(Bookings::TransitionStatus).to receive(:call).and_return(OpenStruct.new(success?: false, error: "transition failed"))

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.failed.sole).to include("booking_id" => booking.id, "reason" => "transition failed")
    expect(booking.reload.status).to eq("checked_in")
  end
end
