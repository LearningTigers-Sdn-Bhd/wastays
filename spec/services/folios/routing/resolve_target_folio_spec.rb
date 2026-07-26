# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::ResolveTargetFolio do
  let(:booking) { create(:booking) }
  let(:hotel) { booking.hotel }
  let!(:guest_folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let!(:company_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel) }
  let(:room_code) { hotel.transaction_codes.find_by!(system_key: "room_revenue") }
  let(:actor) { create(:user, account: hotel.account) }

  def grant_permission(user, slug, hotel)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    role = create(:role, account: hotel.account)
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
  end

  it "falls back to the primary booking folio" do
    result = described_class.call(booking: booking, transaction_code: room_code)

    expect(result.success?).to be(true)
    expect(result.folio).to eq(guest_folio)
    expect(result.route_source).to eq("primary_folio")
  end

  it "uses an active routing rule before fallback" do
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)

    result = described_class.call(booking: booking, transaction_code: room_code)

    expect(result.success?).to be(true)
    expect(result.folio).to eq(company_folio)
    expect(result.route_source).to eq("routing_rule")
    expect(result.route_metadata[:folio_routing_rule_id]).to be_present
  end

  it "inherits the fallback transaction code route when no child rule exists" do
    sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)

    result = described_class.call(
      booking: booking,
      transaction_code: sst_code,
      fallback_transaction_code: room_code
    )

    expect(result).to be_success
    expect(result.folio).to eq(company_folio)
    expect(result.route_source).to eq("follows_parent")
    expect(result.route_metadata[:fallback_transaction_code_id]).to eq(room_code.id)
  end

  it "uses an explicit child rule before the fallback route" do
    sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: sst_code, target_folio: guest_folio)

    result = described_class.call(
      booking: booking,
      transaction_code: sst_code,
      fallback_transaction_code: room_code
    )

    expect(result).to be_success
    expect(result.folio).to eq(guest_folio)
    expect(result.route_source).to eq("routing_rule")
  end

  it "uses a valid manual override before an active routing rule" do
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)
    grant_permission(actor, "manage_folio_movements", hotel)

    result = described_class.call(
      booking: booking,
      transaction_code: room_code,
      override_target_folio: guest_folio,
      override_reason: "Company should not cover this charge",
      actor: actor
    )

    expect(result.success?).to be(true)
    expect(result.folio).to eq(guest_folio)
    expect(result.route_source).to eq("manual_override")
  end

  it "uses parent transaction before override and routing rule" do
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: guest_folio)
    grant_permission(actor, "manage_folio_movements", hotel)
    parent = create(:folio_transaction, booking_folio: company_folio, transaction_code: room_code)

    result = described_class.call(
      booking: booking,
      transaction_code: room_code,
      parent_transaction: parent,
      override_target_folio: guest_folio,
      override_reason: "Override ignored because parent wins",
      actor: actor
    )

    expect(result.success?).to be(true)
    expect(result.folio).to eq(company_folio)
    expect(result.route_source).to eq("follows_parent")
    expect(result.route_metadata[:parent_transaction_id]).to eq(parent.id)
  end

  it "rejects parent transactions from another booking" do
    other_booking = create(:booking, hotel: hotel)
    other_folio = create(:booking_folio, booking: other_booking, hotel: hotel)
    parent = create(:folio_transaction, booking_folio: other_folio, transaction_code: room_code)

    result = described_class.call(booking: booking, transaction_code: room_code, parent_transaction: parent)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Parent transaction must belong to the same booking.")
  end

  it "rejects parent transactions from another hotel" do
    other_parent = create(:folio_transaction)

    result = described_class.call(booking: booking, transaction_code: room_code, parent_transaction: other_parent)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Parent transaction must belong to the same booking.")
  end

  it "requires override reason" do
    grant_permission(actor, "manage_folio_movements", hotel)

    result = described_class.call(booking: booking, transaction_code: room_code, override_target_folio: company_folio, actor: actor)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Override reason can't be blank.")
  end

  it "requires override permission" do
    result = described_class.call(
      booking: booking,
      transaction_code: room_code,
      override_target_folio: company_folio,
      override_reason: "Route differently",
      actor: actor
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("You do not have permission to override folio routing.")
  end

  it "rejects a closed resolved folio" do
    company_folio.update!(status: "closed", closed_at: Time.current, closed_by: actor)
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)

    result = described_class.call(booking: booking, transaction_code: room_code)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Resolved folio must be open.")
  end
end
