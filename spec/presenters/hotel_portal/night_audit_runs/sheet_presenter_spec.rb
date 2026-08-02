# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::NightAuditRuns::SheetPresenter do
  let(:hotel) { build_stubbed(:hotel) }
  let(:business_date) { Date.current }
  let(:clean_evaluation) { { blocked_details: {}, exceptions: {}, summary: {} } }
  let(:manual_audit) { build_stubbed(:night_audit, status: "preparing", trigger_mode: "manual", performed_by_user_id: 12) }

  before do
    relation = instance_double(ActiveRecord::Relation)
    allow(hotel).to receive(:bookings).and_return(relation)
    allow(relation).to receive(:where).and_return(relation)
    allow(relation).to receive(:pluck).and_return([])
  end

  it "selects Confirm and exposes all three progress steps when checks are clear" do
    presenter = described_class.new(hotel:, business_date:, evaluation: clean_evaluation, night_audit: manual_audit)

    expect(presenter.current_step).to eq(:review)
    expect(presenter.steps.map { |step| [ step.key, step.label, step.state ] }).to eq([
      [ :bookings, "Bookings", :complete ],
      [ :payments_charges, "Payments & charges", :complete ],
      [ :review, "Confirm", :current ]
    ])
    expect(presenter).to be_ready_to_run
  end

  it "selects Bookings before financial work when both need attention" do
    evaluation = evaluation_with(
      "due_out_not_checked_out" => [ booking_details(1, "checked_in") ],
      "missing_folio" => [ booking_details(2, "checked_in") ]
    )
    presenter = described_class.new(hotel:, business_date:, evaluation:, night_audit: manual_audit)

    expect(presenter.current_step).to eq(:bookings)
    expect(presenter.steps.map(&:state)).to eq(%i[current upcoming upcoming])
    expect(presenter.booking_items.map(&:type)).to eq([ "due_out_not_checked_out" ])
    expect(presenter.financial_items.map(&:type)).to eq([ "missing_folio" ])
  end

  it "selects Payments & charges when booking work is clear" do
    evaluation = evaluation_with("outstanding_folio_balance" => [ booking_details(2, "completed") ])
    presenter = described_class.new(hotel:, business_date:, evaluation:, night_audit: manual_audit)

    expect(presenter.current_step).to eq(:payments_charges)
    expect(presenter.steps.map(&:state)).to eq(%i[complete current upcoming])
    expect(presenter.financial_items.first.label).to eq("Balance still due")
  end

  it "derives departure actions from the live booking status, not the finding type" do
    allow_live_statuses([ 1, "due_out_detected" ], [ 2, "checkout_required" ], [ 3, "checked_in" ])
    evaluation = evaluation_with(
      "due_out_not_checked_out" => [
        booking_details(1, "checked_in"),
        booking_details(2, "due_out_detected"),
        booking_details(3, "due_out_detected")
      ]
    )
    presenter = described_class.new(hotel:, business_date:, evaluation:, night_audit: manual_audit)

    expect(presenter.booking_items.map { |item| [ item.booking_status, item.actions.map(&:label) ] }).to eq([
      [ "due_out_detected", [ "Handle late checkout" ] ],
      [ "checkout_required", [ "Complete checkout" ] ],
      [ "checked_in", [ "Refresh booking checks" ] ]
    ])
  end

  it "uses a dropdown-sized action set only for a detected missed arrival" do
    allow_live_statuses([ 4, "no_show_detected" ], [ 5, "confirmed" ])
    evaluation = evaluation_with(
      "missed_arrival_not_resolved" => [ booking_details(4, "confirmed"), booking_details(5, "no_show_detected") ]
    )
    presenter = described_class.new(hotel:, business_date:, evaluation:, night_audit: manual_audit)

    detected, raw = presenter.booking_items
    expect(detected.actions.map { |action| [ action.key, action.label ] }).to eq([
      [ :backdated_check_in, "Record an earlier check-in" ],
      [ :mark_no_show, "Mark as no-show" ],
      [ :open_booking, "Open booking" ]
    ])
    expect(raw.actions.map(&:label)).to eq([ "Refresh booking checks" ])
    expect(presenter).to be_detection_needed
  end

  it "describes direct and menu-sized financial actions in plain staff language" do
    evaluation = evaluation_with(
      "missing_folio" => [ booking_details(1, "checked_in") ],
      "missing_nightly_charges" => [ booking_details(2, "checked_in") ],
      "captured_payment_not_synced" => [ booking_details(3, "completed") ],
      "refund_not_synced" => [ booking_details(4, "completed") ]
    )
    presenter = described_class.new(hotel:, business_date:, evaluation:, night_audit: manual_audit)
    items = presenter.financial_items.index_by(&:type)

    expect(items.fetch("missing_folio").actions.map(&:label)).to eq([ "Create folio" ])
    expect(items.fetch("missing_nightly_charges").actions.map(&:label)).to eq([ "Add missing room charges", "Open folio" ])
    expect(items.fetch("captured_payment_not_synced").actions.map(&:label)).to eq([ "Add payment to guest bill" ])
    expect(items.fetch("refund_not_synced").actions.map(&:label)).to eq([ "Add refund to guest bill" ])

    staff_copy = items.values.flat_map { |item| [ item.label, item.description, *item.actions.map(&:label) ] }.join(" ")
    expect(staff_copy).not_to match(/resolver|blocker|transition|exception|synchronization|captured_payment_not_synced|missing_nightly_charges/i)
  end

  it "resumes manual, blocked, and failed audits without losing review ownership" do
    blocked = build_stubbed(:night_audit, status: "blocked", trigger_mode: "manual", performed_by_user_id: 12)
    failed = build_stubbed(:night_audit, status: "failed", trigger_mode: "manual", performed_by_user_id: 12)
    scheduled = build_stubbed(:night_audit, status: "preparing", trigger_mode: "scheduled", performed_by_user_id: nil)

    expect(described_class.new(hotel:, business_date:, evaluation: clean_evaluation, night_audit: manual_audit)).to be_review_started
    expect(described_class.new(hotel:, business_date:, evaluation: clean_evaluation, night_audit: blocked)).to be_review_started
    expect(described_class.new(hotel:, business_date:, evaluation: clean_evaluation, night_audit: failed)).to be_review_started
    expect(described_class.new(hotel:, business_date:, evaluation: clean_evaluation, night_audit: scheduled)).not_to be_review_started
  end

  private

  def evaluation_with(blocked_details)
    { blocked_details:, exceptions: {}, summary: {} }
  end

  def booking_details(id, status)
    { "booking_id" => id, "status" => status, "guest_name" => "Guest #{id}", "confirmation_token" => "WS-#{id}" }
  end

  def allow_live_statuses(*rows)
    allow(hotel.bookings.where(id: rows.map(&:first))).to receive(:pluck).with(:id, :status).and_return(rows)
  end
end
