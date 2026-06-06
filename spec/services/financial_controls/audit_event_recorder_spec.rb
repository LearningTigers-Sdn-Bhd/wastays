# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinancialControls::AuditEventRecorder do
  after do
    Current.reset
  end

  it "creates an audit event with the current request id" do
    hotel = create(:hotel)
    user = create(:user)
    Current.request_id = "request-123"

    event = described_class.call!(
      hotel: hotel,
      business_date: Date.current,
      event_type: "night_audit_started",
      source: "night_audit",
      actor: user,
      metadata: { trigger_mode: "manual" }
    )

    expect(event).to be_persisted
    expect(event.request_id).to eq("request-123")
    expect(event.actor).to eq(user)
    expect(event.metadata).to eq("trigger_mode" => "manual")
  end

  it "derives folio and booking references from a folio transaction" do
    transaction = create(:folio_transaction)
    hotel = transaction.booking_folio.hotel

    event = described_class.call!(
      hotel: hotel,
      business_date: transaction.posting_date,
      event_type: "folio_transaction_created",
      source: "staff",
      folio_transaction: transaction
    )

    expect(event.booking_folio).to eq(transaction.booking_folio)
    expect(event.booking).to eq(transaction.booking_folio.booking)
    expect(event.amount).to eq(transaction.amount)
    expect(event.currency).to eq(transaction.currency || transaction.booking_folio.booking.currency)
  end

  it "accepts system events without an actor" do
    hotel = create(:hotel)

    event = described_class.call!(
      hotel: hotel,
      business_date: Date.current,
      event_type: "night_audit_started",
      source: "night_audit"
    )

    expect(event.actor).to be_nil
  end

  it "derives night audit references from metadata" do
    night_audit = create(:night_audit)

    event = described_class.call!(
      hotel: night_audit.hotel,
      business_date: night_audit.business_date,
      event_type: "folio_transaction_created",
      source: "night_audit",
      metadata: { night_audit_id: night_audit.id }
    )

    expect(event.night_audit).to eq(night_audit)
  end
end
