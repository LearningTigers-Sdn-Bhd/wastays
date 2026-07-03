# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::ResolveBookingAssignment do
  it "keeps tourism tax with the primary guest" do
    booking = create(:booking)
    primary = create(:booking_guest, booking: booking, is_primary: true)

    result = described_class.call(booking: booking, charge_category: "tourism_tax")

    expect(result).to be_success
    expect(result.billing_party).to eq(primary.booking_billing_party)
  end

  it "resolves an ensured company party and its terms" do
    group = create(:group_booking)
    booking = create(:booking, hotel: group.hotel, group_booking: group, group_position: 1)
    create(:booking_room, booking: booking)
    create(:booking_guest, booking: booking, is_primary: true)
    create(:booking_folio, booking: booking, hotel: group.hotel, is_primary: true)
    arrangement = create(:group_billing_arrangement, :company, group_booking: group, hotel: group.hotel)
    assignment = Billing::ApplyGroupArrangement.call(arrangement: arrangement, bookings: [ booking ], charge_categories: [ "accommodation" ]).assignments.sole

    result = described_class.call(booking: booking, charge_category: "accommodation")

    expect(result).to be_success
    expect(result.assignment).to eq(assignment)
    expect(result.billing_party.hotel_corporate_account).to eq(arrangement.hotel_corporate_account)
    expect(result.terms).to eq(result.billing_party.billing_terms)
  end
end
