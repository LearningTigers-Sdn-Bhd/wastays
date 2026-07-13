# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioRouting::ApplyBatch do
  it "applies routing changes as one future-only batch" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    create(:booking_folio, booking:, hotel: booking.hotel, is_primary: true)
    party = create(:booking_billing_party, :company, booking:, hotel: booking.hotel)
    target = create(:booking_folio, :secondary, booking:, hotel: booking.hotel,
      booking_billing_party: party, payer_type: "company", hotel_corporate_account: party.hotel_corporate_account)
    code = create(:transaction_code, hotel: booking.hotel, kind: "charge")

    result = described_class.call(booking:, actor:, confirmation: "future_only", reason: "Company pays", idempotency_key: SecureRandom.uuid,
      routes: { code.id.to_s => { "billing_party_id" => party.id.to_s, "target_folio_id" => target.id.to_s } })

    expect(result).to be_success
    expect(booking.folio_routing_rules.reload.active.find_by!(transaction_code: code).target_folio).to eq(target)
  end

  it "rejects a target folio owned by a different billing party" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    party = create(:booking_billing_party, :company, booking:, hotel: booking.hotel)
    other_party = create(:booking_billing_party, :company, booking:, hotel: booking.hotel)
    target = create(:booking_folio, :secondary, booking:, hotel: booking.hotel,
      booking_billing_party: other_party, payer_type: "company", hotel_corporate_account: other_party.hotel_corporate_account)
    code = create(:transaction_code, hotel: booking.hotel, kind: "charge")

    result = described_class.call(booking:, actor:, confirmation: "future_only", reason: nil, idempotency_key: SecureRandom.uuid,
      routes: { code.id.to_s => { "billing_party_id" => party.id.to_s, "target_folio_id" => target.id.to_s } })

    expect(result).not_to be_success
    expect(result.error).to eq("Target folio must belong to the selected billing party.")
  end

  it "creates and removes an attached-item routing exception" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    booking_guest = create(:booking_guest, booking:)
    guest_party = booking_guest.booking_billing_party
    parent_folio = create(:booking_folio, booking:, hotel: booking.hotel, is_primary: true,
      booking_billing_party: guest_party)
    company_party = create(:booking_billing_party, :company, booking:, hotel: booking.hotel)
    target = create(:booking_folio, :secondary, booking:, hotel: booking.hotel,
      booking_billing_party: company_party, payer_type: "company", hotel_corporate_account: company_party.hotel_corporate_account)
    parent_code = booking.hotel.transaction_codes.find_by!(system_key: "room_revenue")
    child_code = booking.hotel.transaction_codes.find_by!(system_key: "sst_tax")
    key = "primary:sst_tax"

    exception = described_class.call(booking:, actor:, confirmation: nil, reason: "Company covers SST",
      idempotency_key: SecureRandom.uuid, routes: {
        parent_code.id.to_s => {
          "billing_party_id" => guest_party.id.to_s,
          "target_folio_id" => parent_folio.id.to_s,
          "children" => { key => { "billing_party_choice" => "party:#{company_party.id}", "target_folio_id" => target.id.to_s } }
        }
      })

    expect(exception).to be_success
    rule = booking.folio_routing_rules.active.find_by!(transaction_code: child_code)
    expect(rule.target_folio).to eq(target)

    inherited = described_class.call(booking:, actor:, confirmation: nil, reason: "Return SST to parent",
      idempotency_key: SecureRandom.uuid, routes: {
        parent_code.id.to_s => {
          "billing_party_id" => guest_party.id.to_s,
          "target_folio_id" => parent_folio.id.to_s,
          "children" => { key => { "billing_party_choice" => "inherit" } }
        }
      })

    expect(inherited).to be_success
    expect(rule.reload).not_to be_active
  end

  it "normalizes a child selection matching the parent party to inheritance" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    guest = create(:booking_guest, booking:)
    party = guest.booking_billing_party
    parent_folio = create(:booking_folio, booking:, hotel: booking.hotel, is_primary: true, booking_billing_party: party)
    other_folio = create(:booking_folio, booking:, hotel: booking.hotel, is_primary: false, booking_billing_party: party)
    parent_code = booking.hotel.transaction_codes.find_by!(system_key: "room_revenue")

    result = described_class.call(booking:, actor:, confirmation: nil, reason: nil,
      idempotency_key: SecureRandom.uuid, routes: {
        parent_code.id.to_s => {
          "billing_party_id" => party.id.to_s,
          "target_folio_id" => parent_folio.id.to_s,
          "children" => { "primary:sst_tax" => { "billing_party_choice" => "party:#{party.id}", "target_folio_id" => other_folio.id.to_s } }
        }
      })

    expect(result).to be_success
    sst_code = booking.hotel.transaction_codes.find_by!(system_key: "sst_tax")
    expect(booking.folio_routing_rules.active.find_by(transaction_code: sst_code)).to be_nil
  end

  it "routes an attached item to the guest primary folio with the dedicated choice" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    guest = create(:booking_guest, booking:)
    guest_folio = create(:booking_folio, booking:, hotel: booking.hotel, is_primary: true,
      booking_billing_party: guest.booking_billing_party)
    company_party = create(:booking_billing_party, :company, booking:, hotel: booking.hotel)
    company_folio = create(:booking_folio, :secondary, booking:, hotel: booking.hotel,
      booking_billing_party: company_party, payer_type: "company", hotel_corporate_account: company_party.hotel_corporate_account)
    parent_code = booking.hotel.transaction_codes.find_by!(system_key: "room_revenue")
    sst_code = booking.hotel.transaction_codes.find_by!(system_key: "sst_tax")

    result = described_class.call(booking:, actor:, confirmation: "future_only", reason: "Keep tax with guest",
      idempotency_key: SecureRandom.uuid, routes: {
        parent_code.id.to_s => {
          "billing_party_id" => company_party.id.to_s,
          "target_folio_id" => company_folio.id.to_s,
          "children" => { "primary:sst_tax" => { "billing_party_choice" => "guest_primary_folio" } }
        }
      })

    expect(result).to be_success
    expect(booking.folio_routing_rules.active.find_by!(transaction_code: sst_code).target_folio).to eq(guest_folio)
  end

  it "previews booking-local inclusion changes even without a parent route change" do
    booking = create(:booking)
    parent_folio = create(:booking_folio, booking:, hotel: booking.hotel, is_primary: true)
    parent_code = booking.hotel.transaction_codes.find_by!(system_key: "room_revenue")

    preview = described_class.preview(booking:, routes: {
      parent_code.id.to_s => {
        "billing_party_id" => parent_folio.booking_billing_party_id.to_s,
        "target_folio_id" => parent_folio.id.to_s,
        "taxes" => { "primary:sst_tax" => "1" }
      }
    })

    expect(preview).to be_success
    expect(preview.tax_changes.size).to eq(1)
    expect(preview.review_required?).to be(true)
  end

  it "supersedes a group-derived route with a booking-local rule" do
    group = create(:group_booking)
    booking = create(:booking, hotel: group.hotel, group_booking: group)
    actor = create(:user, account: group.hotel.account)
    guest = create(:booking_guest, booking:)
    guest_party = guest.booking_billing_party
    primary = create(:booking_folio, booking:, hotel: group.hotel, is_primary: true, booking_billing_party: guest_party)
    company_party = create(:booking_billing_party, :company, booking:, hotel: group.hotel)
    target = create(:booking_folio, :secondary, booking:, hotel: group.hotel,
      booking_billing_party: company_party, payer_type: "company", hotel_corporate_account: company_party.hotel_corporate_account)
    code = group.hotel.transaction_codes.find_by!(system_key: "room_revenue")
    derived = create(:folio_routing_rule, booking:, hotel: group.hotel, transaction_code: code,
      target_folio: primary, source_type: "group")

    result = described_class.call(booking:, actor:, confirmation: nil, reason: nil, idempotency_key: SecureRandom.uuid,
      routes: { code.id.to_s => { "billing_party_id" => company_party.id.to_s, "target_folio_id" => target.id.to_s } })

    expect(result).to be_success
    expect(derived.reload).not_to be_active
    local = booking.folio_routing_rules.active.find_by!(transaction_code: code)
    expect(local).to have_attributes(source_type: "booking", target_folio_id: target.id)
  end
end
