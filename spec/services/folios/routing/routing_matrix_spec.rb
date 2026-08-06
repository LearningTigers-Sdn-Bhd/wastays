# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::RoutingMatrix do
  it "builds routable rows with rule targets and tax inclusion children" do
    booking = create(:booking)
    hotel = booking.hotel
    primary_folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true, folio_sequence: 1)
    routed_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_sequence: 2)
    tax_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_sequence: 3)
    parent_code = create(:transaction_code, hotel: hotel, code: "ROUTE", kind: "charge")
    create(:transaction_code_tax, transaction_code: parent_code, hotel_tax: nil, primary_tax_key: "sst_tax")
    routing_rule = create(:folio_routing_rule, booking: booking, hotel: hotel, transaction_code: parent_code, target_folio: routed_folio)
    sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
    create(:folio_routing_rule, booking: booking, hotel: hotel, transaction_code: sst_code, target_folio: tax_folio)
    custom_tax = create(:hotel_tax, hotel: hotel, name: "Heritage Fee", code: "HERITAGE")
    create(:booking_tax_inclusion_override, booking: booking, hotel: hotel, transaction_code: parent_code,
      primary_tax_key: "sst_tax", action: "exclude")
    create(:booking_tax_inclusion_override, booking: booking, hotel: hotel, transaction_code: parent_code,
      primary_tax_key: nil, hotel_tax: custom_tax, action: "include")
    allow(Folios::Routing::RoutabilityPolicy).to receive(:parent_codes).with(hotel: hotel).and_return([ parent_code ])

    matrix = described_class.new(booking: booking)
    row = matrix.rows.fetch(0)
    sst_child = row.children.find { |child| child.key == "primary:sst_tax" }
    custom_child = row.children.find { |child| child.key == "hotel_tax:#{custom_tax.id}" }

    expect(row).to have_attributes(code: parent_code, rule: routing_rule, target_folio: routed_folio)
    expect(sst_child).to have_attributes(label: "SST 8%", included: false, rule: FolioRoutingRule.find_by(transaction_code: sst_code), target_folio: tax_folio)
    expect(custom_child).to have_attributes(code: custom_tax.transaction_code, label: "Heritage Fee", included: true, rule: nil, target_folio: nil)
    expect(row.included_children).to contain_exactly(custom_child)
    expect(matrix.folios).to eq([ primary_folio, routed_folio, tax_folio ])
  end

  it "uses the primary folio as the default target and lists active billing parties" do
    booking = create(:booking)
    hotel = booking.hotel
    primary_folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
    parent_code = create(:transaction_code, hotel: hotel, kind: "charge")
    active_party = create(:booking_billing_party, :company, booking: booking, hotel: hotel)
    archived_party = create(:booking_billing_party, :company, booking: booking, hotel: hotel, archived_at: Time.current)
    allow(Folios::Routing::RoutabilityPolicy).to receive(:parent_codes).with(hotel: hotel).and_return([ parent_code ])

    matrix = described_class.new(booking: booking)

    expect(matrix.rows.fetch(0)).to have_attributes(code: parent_code, rule: nil, target_folio: primary_folio)
    expect(matrix.parties).to eq([ active_party ])
    expect(matrix.parties).not_to include(archived_party)
  end
end
