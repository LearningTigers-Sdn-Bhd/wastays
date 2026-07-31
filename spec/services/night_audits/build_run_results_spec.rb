# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::BuildRunResults do
  let(:hotel) { create(:hotel) }
  let(:night_audit) { create(:night_audit, hotel: hotel, status: "running") }

  it "summarizes status changes, posted charges, and deduplicated logged items" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    create(:booking_audit_log,
      hotel: hotel,
      auditable: booking,
      source: "night_audit",
      action_type: "status_change",
      old_value: { "status" => "checked_in" },
      new_value: { "status" => "due_out_detected" },
      metadata: { night_audit_id: night_audit.id })
    transaction = create(:folio_transaction,
      booking_folio: folio,
      night_audit: night_audit,
      amount: 125,
      metadata: { night_audit_id: night_audit.id, booking_id: booking.id })
    item = { "item_key" => "duplicate-key", "item_type" => "nightly_charge", "reason" => "Nightly charge already posted" }
    2.times do
      NightAuditLog.create!(night_audit: night_audit, hotel: hotel, action_type: "item_skipped", metadata: { item: item })
    end

    result = described_class.call(night_audit: night_audit)

    expect(result.dig("status_changes", "count")).to eq(1)
    expect(result.dig("charges_posted", "count")).to eq(1)
    expect(result.dig("charges_posted", "total")).to eq("125.0")
    expect(result.dig("charges_posted", "items").sole["folio_transaction_id"]).to eq(transaction.id)
    expect(result.dig("skipped_items", "count")).to eq(1)
  end

  it "uses direct linkage instead of metadata-only linkage for posted charges" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    linked = create(:folio_transaction,
      booking_folio: folio,
      night_audit: night_audit,
      amount: 125,
      metadata: { night_audit_id: night_audit.id })
    create(:folio_transaction,
      booking_folio: folio,
      amount: 75,
      metadata: { night_audit_id: night_audit.id })

    result = described_class.call(night_audit: night_audit)

    expect(result.dig("charges_posted", "count")).to eq(1)
    expect(result.dig("charges_posted", "total")).to eq("125.0")
    expect(result.dig("charges_posted", "items").sole["folio_transaction_id"]).to eq(linked.id)
  end

  it "keeps orphaned booking audit logs without crashing" do
    missing_booking_id = Booking.maximum(:id).to_i + 10_000
    log = create(:booking_audit_log,
      hotel: hotel,
      source: "night_audit",
      action_type: "status_change",
      old_value: { "status" => "confirmed" },
      new_value: { "status" => "no_show_detected" },
      metadata: { night_audit_id: night_audit.id }
    )
    log.update_columns(auditable_id: missing_booking_id)

    result = described_class.call(night_audit: night_audit)

    item = result.dig("status_changes", "items").sole
    expect(item["item_key"]).to eq("booking_audit_log:#{log.id}")
    expect(item["booking_id"]).to eq(missing_booking_id)
    expect(item["confirmation_token"]).to be_nil
    expect(item["guest_name"]).to eq("Deleted booking")
    expect(item["from"]).to eq("confirmed")
    expect(item["to"]).to eq("no_show_detected")
  end
end
