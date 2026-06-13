# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelOps::BuildNightAuditRunResults do
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
      new_value: { "status" => "review_due_out" },
      metadata: { night_audit_id: night_audit.id })
    transaction = create(:folio_transaction,
      booking_folio: folio,
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
end
