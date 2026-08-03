# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::StartManualReview do
  let(:business_date) { Date.current - 1.day }
  let(:hotel) { create(:hotel, :without_current_business_date, time_zone: "Kuala Lumpur") }
  let(:actor) { create(:user, account: hotel.account) }

  before do
    BusinessDates::ResetAuthority.call!(hotel:, date: business_date)
    allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel:).and_return(true)
  end

  it "creates a manual preparation and detects eligible guest stays with audit evidence" do
    due_out = create(:booking, hotel:, status: "checked_in", check_in: business_date - 1.day, check_out: business_date, checked_in_at: 1.day.ago)
    arrival = create(:booking, hotel:, status: "confirmed", check_in: business_date, check_out: business_date + 1.day)

    result = described_class.call(hotel:, business_date:, actor:)

    expect(result).to be_success
    expect(result.night_audit).to have_attributes(status: "preparing", trigger_mode: "manual", performed_by_user: actor)
    expect(result).to have_attributes(due_outs_detected_count: 1, missed_arrivals_detected_count: 1)
    expect(due_out.reload.status).to eq("due_out_detected")
    expect(arrival.reload.status).to eq("no_show_detected")
    expect(result.night_audit.night_audit_logs.where(action_type: "item_detected").count).to eq(2)
    expect(result.night_audit.night_audit_logs.where(action_type: "item_detected").pluck(:metadata)).to all(include("before", "after", "business_date" => business_date.iso8601))
    expect(hotel.current_business_date_record).to be_open
  end

  it "is idempotent when the review is started repeatedly" do
    booking = create(:booking, hotel:, status: "checked_in", check_in: business_date - 1.day, check_out: business_date, checked_in_at: 1.day.ago)

    first = described_class.call(hotel:, business_date:, actor:)
    second = described_class.call(hotel:, business_date:, actor:)

    expect(first.due_outs_detected_count).to eq(1)
    expect(second.detected_count).to eq(0)
    expect(booking.reload.status).to eq("due_out_detected")
    expect(first.night_audit.night_audit_logs.where(action_type: "item_detected").count).to eq(1)
  end

  it "takes manual ownership of a scheduled preparation" do
    audit = create(:night_audit, hotel:, business_date:, status: "preparing", trigger_mode: "scheduled", performed_by_user: nil)

    result = described_class.call(hotel:, business_date:, actor:)

    expect(result).to be_success
    expect(audit.reload).to have_attributes(trigger_mode: "manual", performed_by_user: actor)
  end

  it "preserves already detected and checkout-required statuses" do
    due_out = create(:booking, hotel:, status: "due_out_detected", check_in: business_date - 1.day, check_out: business_date, checked_in_at: 1.day.ago)
    no_show = create(:booking, hotel:, status: "no_show_detected", check_in: business_date, check_out: business_date + 1.day, no_show_detected_business_date: business_date)
    checkout = create(:booking, hotel:, status: "checkout_required", check_in: business_date - 1.day, check_out: business_date, checked_in_at: 1.day.ago)

    result = described_class.call(hotel:, business_date:, actor:)

    expect(result.detected_count).to eq(0)
    expect([ due_out.reload.status, no_show.reload.status, checkout.reload.status ]).to eq(%w[due_out_detected no_show_detected checkout_required])
  end

  it "stores transition failures as system blockers" do
    failed_item = { "booking_id" => 42, "confirmation_token" => "FAIL-42", "reason" => "transition failed" }
    due_out_result = NightAudits::DetectDueOuts::Result.new(detected: [], skipped: [], failed: [ failed_item ])
    allow(NightAudits::DetectDueOuts).to receive(:call).and_return(due_out_result)

    result = described_class.call(hotel:, business_date:, actor:)

    expect(result).to be_success
    expect(result.failures).to contain_exactly(failed_item)
    expect(result.evaluation[:blocked_details]["detection_failures"]).to contain_exactly(failed_item)
    expect(result.night_audit.reload.blocked_details["detection_failures"]).to contain_exactly(failed_item)
    expect(result.night_audit.night_audit_logs.where(action_type: "item_failed")).to exist
  end

  it "rejects early or unauthorized review starts without creating an audit" do
    allow(hotel).to receive(:can_audit_date?).with(business_date).and_return(false)
    early = described_class.call(hotel:, business_date:, actor:)
    allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel:).and_return(false)
    unauthorized = described_class.call(hotel:, business_date:, actor:)

    expect(early).not_to be_success
    expect(unauthorized).not_to be_success
    expect(hotel.night_audits).to be_empty
  end
end
