# frozen_string_literal: true

require "rails_helper"

RSpec.describe "group billing services" do
  it "assigns a corporate payer and idempotently ensures one child folio" do
    group = create(:group_booking)
    booking = create(:booking, hotel: group.hotel, group_booking: group, group_position: 1)
    create(:booking_room, booking: booking)
    create(:booking_folio, booking: booking, hotel: group.hotel, is_primary: true)
    arrangement = create(:group_billing_arrangement, :company, group_booking: group, hotel: group.hotel)

    result = Billing::ApplyGroupArrangement.call(
      arrangement: arrangement,
      bookings: [ booking ],
      charge_categories: [ "accommodation" ]
    )
    repeated = Billing::EnsureCorporateFolio.call(booking: booking, arrangement: arrangement)

    expect(result).to be_success
    expect(repeated).to be_success
    expect(booking.booking_folios.where(
      payer_type: "company",
      hotel_corporate_account: arrangement.hotel_corporate_account
    ).count).to eq(1)
    expect(repeated.folio.booking_billing_party.hotel_corporate_account).to eq(arrangement.hotel_corporate_account)
    expect(repeated.folio.booking_billing_party.billing_terms).to be_present
  end

  it "preserves booking-local exceptions during a group application by default" do
    group = create(:group_booking)
    booking = create(:booking, hotel: group.hotel, group_booking: group, group_position: 1)
    local = create(:group_billing_arrangement, group_booking: group, hotel: group.hotel, name: "Local payer")
    group_default = create(:group_billing_arrangement, group_booking: group, hotel: group.hotel, name: "Group payer")
    assignment = BookingBillingAssignment.create!(booking: booking, group_billing_arrangement: local, charge_category: "accommodation", local_exception: true)

    result = Billing::ApplyGroupArrangement.call(arrangement: group_default, bookings: [ booking ], charge_categories: [ "accommodation" ])

    expect(result).to be_success
    expect(result.skipped_assignments).to eq([ assignment ])
    expect(assignment.reload.group_billing_arrangement).to eq(local)
  end

  it "keeps a booking-local assignment from changing its group arrangement" do
    assignment = create_assignment(local_exception: true)

    assignment.update!(coverage: { "percentage" => 50 })

    expect(assignment.group_billing_arrangement.reload.coverage).to eq({})
  end

  def create_assignment(local_exception:)
    group = create(:group_booking)
    booking = create(:booking, hotel: group.hotel, group_booking: group, group_position: 1)
    arrangement = create(:group_billing_arrangement, group_booking: group, hotel: group.hotel)
    BookingBillingAssignment.create!(
      booking: booking,
      group_billing_arrangement: arrangement,
      charge_category: "accommodation",
      local_exception: local_exception
    )
  end
end
