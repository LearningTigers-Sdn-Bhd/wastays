# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::ApplyGroupBatch do
  it "applies routing changes across group siblings and skips bookings with no diff" do
    group = create(:group_booking)
    hotel = group.hotel
    actor = create(:user, account: hotel.account)
    booking_a = create(:booking, hotel:, group_booking: group)
    booking_b = create(:booking, hotel:, group_booking: group)
    folio_a = create(:booking_folio, booking: booking_a, hotel:, is_primary: true)
    party_a = create(:booking_billing_party, :company, booking: booking_a, hotel:)
    target_a = create(:booking_folio, :secondary, booking: booking_a, hotel:,
      booking_billing_party: party_a, payer_type: "company", hotel_corporate_account: party_a.hotel_corporate_account)
    folio_b = create(:booking_folio, booking: booking_b, hotel:, is_primary: true)
    code = create(:transaction_code, hotel:, kind: "charge")
    key = SecureRandom.uuid

    result = described_class.call(
      group_booking: group, actor:, confirmation: "future_only", reason: "Split group billing", idempotency_key: key,
      booking_routes: {
        booking_a.id.to_s => { code.id.to_s => { "billing_party_id" => party_a.id.to_s, "target_folio_id" => target_a.id.to_s } },
        booking_b.id.to_s => { code.id.to_s => { "target_folio_id" => folio_b.id.to_s } }
      }
    )

    expect(result).to be_success
    expect(result.touched_booking_ids).to eq([ booking_a.id ])
    expect(booking_a.folio_routing_rules.reload.active.find_by!(transaction_code: code).target_folio).to eq(target_a)
    expect(booking_b.folio_routing_rules.reload.active.where(transaction_code: code)).to be_empty

    batch = group.group_billing_change_batches.find_by!(idempotency_key: key)
    expect(batch.status).to eq("completed")
    expect(BillingRouteBatch.where(booking: booking_a).count).to eq(1)
    expect(BillingRouteBatch.where(booking: booking_b).count).to eq(0)
    expect(BookingAuditLog.where(auditable: group, action_type: "group_billing_routes_changed").count).to eq(1)
    expect(BookingAuditLog.where(auditable: booking_a, action_type: "billing_routes_changed").count).to eq(1)
    expect(BookingAuditLog.where(auditable: booking_b, action_type: "billing_routes_changed").count).to eq(0)
  end

  it "rejects a booking that does not belong to the group" do
    group = create(:group_booking)
    booking_a = create(:booking, hotel: group.hotel, group_booking: group)
    outsider = create(:booking, hotel: group.hotel)
    code = create(:transaction_code, hotel: group.hotel, kind: "charge")

    result = described_class.call(
      group_booking: group, actor: nil, confirmation: nil, reason: nil, idempotency_key: SecureRandom.uuid,
      booking_routes: {
        booking_a.id.to_s => { code.id.to_s => {} },
        outsider.id.to_s => { code.id.to_s => {} }
      }
    )

    expect(result).not_to be_success
    expect(result.error).to eq("One or more selected bookings are not part of this group.")
  end

  it "rolls back every booking in the batch when one sibling fails" do
    group = create(:group_booking)
    hotel = group.hotel
    actor = create(:user, account: hotel.account)
    booking_a = create(:booking, hotel:, group_booking: group)
    booking_b = create(:booking, hotel:, group_booking: group)
    party_a = create(:booking_billing_party, :company, booking: booking_a, hotel:)
    target_a = create(:booking_folio, :secondary, booking: booking_a, hotel:,
      booking_billing_party: party_a, payer_type: "company", hotel_corporate_account: party_a.hotel_corporate_account)
    party_b = create(:booking_billing_party, :company, booking: booking_b, hotel:)
    other_party_b = create(:booking_billing_party, :company, booking: booking_b, hotel:)
    mismatched_target_b = create(:booking_folio, :secondary, booking: booking_b, hotel:,
      booking_billing_party: other_party_b, payer_type: "company", hotel_corporate_account: other_party_b.hotel_corporate_account)
    code = create(:transaction_code, hotel:, kind: "charge")
    key = SecureRandom.uuid

    result = described_class.call(
      group_booking: group, actor:, confirmation: "future_only", reason: "Attempt", idempotency_key: key,
      booking_routes: {
        booking_a.id.to_s => { code.id.to_s => { "billing_party_id" => party_a.id.to_s, "target_folio_id" => target_a.id.to_s } },
        booking_b.id.to_s => { code.id.to_s => { "billing_party_id" => party_b.id.to_s, "target_folio_id" => mismatched_target_b.id.to_s } }
      }
    )

    expect(result).not_to be_success
    expect(result.error).to include("Booking No. #{booking_b.formatted_reservation_number}")
    expect(booking_a.folio_routing_rules.reload.active.where(transaction_code: code)).to be_empty
    expect(group.group_billing_change_batches.reload.where(idempotency_key: key)).to be_empty
  end

  it "is a safe no-op when retried with the same idempotency key and payload" do
    group = create(:group_booking)
    hotel = group.hotel
    actor = create(:user, account: hotel.account)
    booking_a = create(:booking, hotel:, group_booking: group)
    create(:booking_folio, booking: booking_a, hotel:, is_primary: true)
    party_a = create(:booking_billing_party, :company, booking: booking_a, hotel:)
    target_a = create(:booking_folio, :secondary, booking: booking_a, hotel:,
      booking_billing_party: party_a, payer_type: "company", hotel_corporate_account: party_a.hotel_corporate_account)
    code = create(:transaction_code, hotel:, kind: "charge")
    key = SecureRandom.uuid
    routes = { booking_a.id.to_s => { code.id.to_s => { "billing_party_id" => party_a.id.to_s, "target_folio_id" => target_a.id.to_s } } }

    first = described_class.call(group_booking: group, actor:, confirmation: "future_only", reason: "Route", idempotency_key: key, booking_routes: routes)
    second = described_class.call(group_booking: group, actor:, confirmation: "future_only", reason: "Route", idempotency_key: key, booking_routes: routes)

    expect(first).to be_success
    expect(second).to be_success
    expect(group.group_billing_change_batches.where(idempotency_key: key).count).to eq(1)
    expect(BillingRouteBatch.where(booking: booking_a).count).to eq(1)
  end

  it "rejects a retry with the same idempotency key but a different payload" do
    group = create(:group_booking)
    hotel = group.hotel
    actor = create(:user, account: hotel.account)
    booking_a = create(:booking, hotel:, group_booking: group)
    create(:booking_folio, booking: booking_a, hotel:, is_primary: true)
    party_a = create(:booking_billing_party, :company, booking: booking_a, hotel:)
    target_a = create(:booking_folio, :secondary, booking: booking_a, hotel:,
      booking_billing_party: party_a, payer_type: "company", hotel_corporate_account: party_a.hotel_corporate_account)
    other_target_a = create(:booking_folio, :secondary, booking: booking_a, hotel:,
      booking_billing_party: party_a, payer_type: "company", hotel_corporate_account: party_a.hotel_corporate_account)
    code = create(:transaction_code, hotel:, kind: "charge")
    key = SecureRandom.uuid

    first = described_class.call(group_booking: group, actor:, confirmation: "future_only", reason: "Route", idempotency_key: key,
      booking_routes: { booking_a.id.to_s => { code.id.to_s => { "billing_party_id" => party_a.id.to_s, "target_folio_id" => target_a.id.to_s } } })
    second = described_class.call(group_booking: group, actor:, confirmation: "future_only", reason: "Route", idempotency_key: key,
      booking_routes: { booking_a.id.to_s => { code.id.to_s => { "billing_party_id" => party_a.id.to_s, "target_folio_id" => other_target_a.id.to_s } } })

    expect(first).to be_success
    expect(second).not_to be_success
    expect(second.error).to eq("This idempotency key was already used for a different group billing change.")
    expect(booking_a.folio_routing_rules.reload.active.find_by!(transaction_code: code).target_folio).to eq(target_a)
  end

  it "aggregates preview counts and review_required? across bookings" do
    group = create(:group_booking)
    hotel = group.hotel
    booking_a = create(:booking, hotel:, group_booking: group)
    booking_b = create(:booking, hotel:, group_booking: group)
    create(:booking_folio, booking: booking_a, hotel:, is_primary: true)
    create(:booking_folio, booking: booking_b, hotel:, is_primary: true)
    parent_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    folio_a = booking_a.booking_folio
    folio_b = booking_b.booking_folio

    preview = described_class.preview(group_booking: group, booking_routes: {
      booking_a.id.to_s => { parent_code.id.to_s => { "billing_party_id" => folio_a.booking_billing_party_id.to_s, "target_folio_id" => folio_a.id.to_s, "taxes" => { "primary:sst_tax" => "1" } } },
      booking_b.id.to_s => { parent_code.id.to_s => { "billing_party_id" => folio_b.booking_billing_party_id.to_s, "target_folio_id" => folio_b.id.to_s, "taxes" => { "primary:sst_tax" => "1" } } }
    })

    expect(preview).to be_success
    expect(preview.bookings.size).to eq(2)
    expect(preview.review_required?).to be(true)
  end
end
