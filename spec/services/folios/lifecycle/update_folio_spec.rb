# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Lifecycle::UpdateFolio do
  let(:booking) { create(:booking, status: "checked_in") }
  let(:user) { create(:user, :superadmin) }
  let(:folio) { create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel) }
  let(:hotel_corporate_account) { create(:hotel_corporate_account, hotel: booking.hotel) }

  it "coerces locked payer types and logs the normalized values" do
    result = described_class.call(
      folio: folio,
      user: user,
      attributes: {
        folio_type: "house",
        payer_type: "company",
        reason: "House use"
      }
    )

    expect(result).to be_success
    expect(folio.reload).to be_folio_type_house
    expect(folio.payer_type).to eq("hotel")
    expect(FolioOperationLog.last.metadata.dig("changes", "payer_type", "to")).to eq("hotel")
    expect(folio.hotel_corporate_account).to be_nil
  end

  it "assigns a Company & Government account and logs it" do
    result = described_class.call(
      folio: folio,
      user: user,
      attributes: {
        folio_type: "external",
        payer_type: "company",
        hotel_corporate_account_id: hotel_corporate_account.id,
        reason: "Bill company"
      }
    )

    expect(result).to be_success
    expect(folio.reload.hotel_corporate_account).to eq(hotel_corporate_account)
    expect(FolioOperationLog.last.metadata.dig("changes", "hotel_corporate_account_id", "to")).to eq(hotel_corporate_account.id)
  end

  it "rejects Company & Government accounts from another hotel" do
    other_relationship = create(:hotel_corporate_account)

    result = described_class.call(
      folio: folio,
      user: user,
      attributes: { folio_type: "external", payer_type: "company", hotel_corporate_account_id: other_relationship.id }
    )

    expect(result).not_to be_success
    expect(result.error).to include("must belong to the folio hotel")
  end

  it "promotes a primary only within the folio's room scope" do
    group_booking = create(:group_booking, hotel: booking.hotel)
    booking.update!(group_booking: group_booking, group_position: 1)
    sibling = create(:booking, hotel: booking.hotel, group_booking: group_booking, group_position: 2)
    booking_primary = create(:booking_folio, booking: booking, hotel: booking.hotel)
    room = create(:booking_room, booking: booking)
    sibling_room = create(:booking_room, booking: sibling)
    old_room_primary = create(:booking_folio, booking: booking, hotel: booking.hotel, booking_room: room)
    new_room_primary = create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel, booking_room: room)
    sibling_primary = create(:booking_folio, booking: sibling, hotel: booking.hotel, booking_room: sibling_room)

    result = described_class.call(
      folio: new_room_primary,
      user: user,
      attributes: {
        is_primary: true,
        set_folio_as_primary_reason: "Guest changed payer"
      }
    )

    expect(result).to be_success
    expect(group_booking.bookings.reload).to all(satisfy { |child| child.booking_rooms.one? })
    expect(new_room_primary.reload).to be_is_primary
    expect(old_room_primary.reload).not_to be_is_primary
    expect(booking_primary.reload).to be_is_primary
    expect(sibling_primary.reload).to be_is_primary
    expect(FolioOperationLog.last.metadata["booking_room_id"]).to eq(room.id)
  end
end
