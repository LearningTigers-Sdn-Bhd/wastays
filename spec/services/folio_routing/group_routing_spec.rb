# frozen_string_literal: true

require "rails_helper"

RSpec.describe "group folio routing" do
  it "uses a group-derived route only during its effective dates" do
    booking, source, target, code, arrangement, assignment = routing_context
    rule = create_rule(booking, target, code, arrangement, assignment, effective_from: Date.current + 1)

    before_date = Folios::ResolveTargetFolio.call(booking: booking, transaction_code: code, posting_date: Date.current)
    on_date = Folios::ResolveTargetFolio.call(booking: booking, transaction_code: code, posting_date: Date.current + 1)

    expect(before_date.folio).to eq(source)
    expect(on_date.folio).to eq(target)
    expect(on_date.route_metadata).to include(folio_routing_rule_id: rule.id)
  end

  it "previews eligible existing charges without moving them" do
    booking, source, target, code, arrangement, assignment = routing_context
    rule = create_rule(booking, target, code, arrangement, assignment)
    transaction = create(:folio_transaction, booking_folio: source, transaction_code: code, transaction_type: "charge", category: "accommodation", amount: 125)

    preview = FolioRouting::PreviewExistingCharges.call(rule: rule)

    expect(preview.transactions).to eq([ transaction ])
    expect(preview.count).to eq(1)
    expect(preview.amount).to eq(125.to_d)
    expect(transaction.reload.booking_folio).to eq(source)
  end

  def routing_context
    group = create(:group_booking)
    booking = create(:booking, hotel: group.hotel, group_booking: group, group_position: 1)
    create(:booking_room, booking: booking)
    source = create(:booking_folio, booking: booking, hotel: group.hotel, is_primary: true)
    target = create(:booking_folio, booking: booking, hotel: group.hotel, is_primary: false)
    code = create(:transaction_code, hotel: group.hotel)
    arrangement = create(:group_billing_arrangement, group_booking: group, hotel: group.hotel)
    assignment = BookingBillingAssignment.create!(booking: booking, group_billing_arrangement: arrangement, charge_category: "accommodation")
    [ booking, source, target, code, arrangement, assignment ]
  end

  def create_rule(booking, target, code, arrangement, assignment, effective_from: nil)
    FolioRoutingRule.create!(
      hotel: booking.hotel,
      booking: booking,
      transaction_code: code,
      target_folio: target,
      source_type: "group",
      group_billing_arrangement: arrangement,
      booking_billing_assignment: assignment,
      effective_from: effective_from
    )
  end
end
