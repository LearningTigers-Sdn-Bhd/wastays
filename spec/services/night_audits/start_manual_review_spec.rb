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

  describe "refreshing a blocked audit" do
    let!(:audit) { create(:night_audit, hotel:, business_date:, status: "blocked", trigger_mode: "scheduled", performed_by_user: nil) }

    before do
      hotel.current_business_date_record.update!(status: "audit_blocked", blockers_snapshot: { "stale" => [] })
      audit.update!(blocked_details: { "detection_failures" => [ { "reason" => "Old failure" } ] })
    end

    it "detects overdue stays and refreshes post-close snapshots without changing audit ownership" do
      booking = create(:booking, hotel:, status: "checked_in", check_in: business_date - 1.day, check_out: business_date, checked_in_at: 1.day.ago)
      create(:booking_room, booking:, nightly_rate_snapshot: { business_date.iso8601 => { "price" => "100" } })
      create(:booking_folio, booking:, hotel:)
      expect(NightAudits::Evaluate).to receive(:new).with(hotel:, business_date:, phase: :post_close).twice.and_call_original

      result = described_class.call(hotel:, business_date:, actor:)

      expect(result).to be_success
      expect(booking.reload.status).to eq("due_out_detected")
      expect(audit.reload).to have_attributes(status: "blocked", trigger_mode: "scheduled", performed_by_user_id: nil)
      expect(audit.blocked_details).not_to have_key("detection_failures")
      expect(audit.summary["manual_review"]).to include("started_by_user_id" => actor.id, "due_outs_detected_count" => 1)
      expect(hotel.current_business_date_record).to have_attributes(status: "audit_blocked", blockers_snapshot: audit.blocked_details)

      repeated = described_class.call(hotel:, business_date:, actor:)
      expect(repeated).to be_success
      expect(repeated.detected_count).to eq(0)
      expect(audit.night_audit_logs.where(action_type: "item_detected").count).to eq(1)
    end

    it "replaces old detection failures and stores the new business-date snapshot" do
      item = { "booking_id" => 42, "reason" => "New failure" }
      allow(NightAudits::DetectDueOuts).to receive(:call).and_return(
        NightAudits::DetectDueOuts::Result.new(detected: [], skipped: [], failed: [ item ])
      )

      result = described_class.call(hotel:, business_date:, actor:)

      expect(result).to be_success
      expect(audit.reload.blocked_details["detection_failures"]).to eq([ item ])
      expect(hotel.current_business_date_record.blockers_snapshot).to eq(audit.blocked_details)
    end

    it "retains missing nightly charges and warnings in the refreshed snapshot" do
      evaluation = {
        blocked_details: { "missing_nightly_charges" => [ { "booking_id" => 42 } ] },
        exceptions: { "open_operational_requests" => [ { "booking_id" => 43 } ] },
        summary: { "checked_in_count" => 2 }
      }
      allow(NightAudits::Evaluate).to receive(:new).with(hotel:, business_date:, phase: :post_close)
        .and_return(instance_double(NightAudits::Evaluate, call: evaluation))

      result = described_class.call(hotel:, business_date:, actor:)

      expect(result).to be_success
      expect(audit.reload.blocked_details).to eq(evaluation[:blocked_details])
      expect(audit.exceptions).to eq(evaluation[:exceptions])
      expect(audit.summary).to include(evaluation[:summary])
      expect(hotel.current_business_date_record.blockers_snapshot).to eq(evaluation[:blocked_details])
    end

    it "rejects unauthorized and early refreshes without detection" do
      expect(NightAudits::DetectDueOuts).not_to receive(:call)
      allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel:).and_return(false)
      expect(described_class.call(hotel:, business_date:, actor:)).not_to be_success
      allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel:).and_return(true)
      allow(hotel).to receive(:can_audit_date?).with(business_date).and_return(false)
      expect(described_class.call(hotel:, business_date:, actor:)).not_to be_success
    end

    %w[pending running completed failed].each do |status|
      it "rejects an audit that is #{status}" do
        audit.update!(status:)
        expect(NightAudits::DetectDueOuts).not_to receive(:call)
        expect(described_class.call(hotel:, business_date:, actor:)).not_to be_success
        expect(audit.reload.status).to eq(status)
      end
    end

    it "rejects a different business date" do
      allow(hotel).to receive(:can_audit_date?).and_return(true)
      expect(NightAudits::DetectDueOuts).not_to receive(:call)
      expect(described_class.call(hotel:, business_date: business_date + 1.day, actor:)).not_to be_success
      expect(audit.reload).to be_blocked
    end
  end
end
