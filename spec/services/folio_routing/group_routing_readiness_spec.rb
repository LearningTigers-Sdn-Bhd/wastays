# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioRouting::GroupRoutingReadiness do
  it "reports a code as not yet routed when no sibling has a rule for it" do
    group = create(:group_booking)
    hotel = group.hotel
    booking_a = create(:booking, hotel:, group_booking: group)
    booking_b = create(:booking, hotel:, group_booking: group)
    create(:booking_folio, booking: booking_a, hotel:, is_primary: true)
    create(:booking_folio, booking: booking_b, hotel:, is_primary: true)
    code = create(:transaction_code, hotel:, kind: "charge")

    status = described_class.new(group_booking: group).code_status(code)

    expect(status.state).to eq(:not_routed)
  end

  it "reports a code as consistent when every sibling resolves the same target folio" do
    group = create(:group_booking)
    hotel = group.hotel
    booking_a = create(:booking, hotel:, group_booking: group)
    booking_b = create(:booking, hotel:, group_booking: group)
    folio_a = create(:booking_folio, booking: booking_a, hotel:, is_primary: true)
    folio_b = create(:booking_folio, booking: booking_b, hotel:, is_primary: true)
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    create(:folio_routing_rule, booking: booking_a, hotel:, transaction_code: code, target_folio: folio_a, source_type: "booking")
    create(:folio_routing_rule, booking: booking_b, hotel:, transaction_code: code, target_folio: folio_b, source_type: "booking")

    status = described_class.new(group_booking: group).code_status(code)

    expect(status.state).to eq(:consistent)
  end

  it "reports a code as inconsistent when siblings resolve to different folios" do
    group = create(:group_booking)
    hotel = group.hotel
    booking_a = create(:booking, hotel:, group_booking: group)
    booking_b = create(:booking, hotel:, group_booking: group)
    party_a = create(:booking_billing_party, :company, booking: booking_a, hotel:)
    folio_a = create(:booking_folio, :secondary, booking: booking_a, hotel:,
      booking_billing_party: party_a, payer_type: "company", hotel_corporate_account: party_a.hotel_corporate_account)
    create(:booking_folio, booking: booking_b, hotel:, is_primary: true)
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    create(:folio_routing_rule, booking: booking_a, hotel:, transaction_code: code, target_folio: folio_a, source_type: "booking")

    status = described_class.new(group_booking: group).code_status(code)

    expect(status.state).to eq(:inconsistent)
    expect(status.folio_count).to eq(2)
  end

  it "flags a booking as not ready when it has no active billing party" do
    group = create(:group_booking)
    hotel = group.hotel
    booking = create(:booking, hotel:, group_booking: group)
    create(:booking_folio, booking:, hotel:, is_primary: true)

    status = described_class.new(group_booking: group).booking_status(booking)

    expect(status.ready).to be(false)
    expect(status.reason).to eq("No billing party assigned")
  end

  it "flags a booking as not ready when it has a party but no open folio" do
    group = create(:group_booking)
    hotel = group.hotel
    booking = create(:booking, hotel:, group_booking: group)
    create(:booking_billing_party, :company, booking:, hotel:)
    create(:booking_folio, booking:, hotel:, is_primary: true, status: "closed")

    status = described_class.new(group_booking: group).booking_status(booking)

    expect(status.ready).to be(false)
    expect(status.reason).to eq("No open folio")
  end

  it "marks a booking ready when it has an active billing party and an open folio" do
    group = create(:group_booking)
    hotel = group.hotel
    booking = create(:booking, hotel:, group_booking: group)
    create(:booking_billing_party, :company, booking:, hotel:)
    create(:booking_folio, booking:, hotel:, is_primary: true)

    status = described_class.new(group_booking: group).booking_status(booking)

    expect(status.ready).to be(true)
    expect(status.reason).to be_nil
  end
end
