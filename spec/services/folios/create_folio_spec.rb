# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::CreateFolio do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", currency: "MYR") }
  let(:user) { create(:user, :superadmin) }
  let(:hotel_corporate_account) { create(:hotel_corporate_account, hotel: hotel) }
  let!(:guest_folio) { create(:booking_folio, hotel: hotel, booking: booking, folio_number: 101, name: "Guest Folio") }
  let!(:company_folio) { create(:booking_folio, :secondary, hotel: hotel, booking: booking, folio_number: 102, name: "Company Folio") }

  it "creates a non-primary folio and records an operation log" do
    expect {
      @result = described_class.call(booking: booking, user: user, attributes: { name: "Incidentals", folio_type: "external", payer_type: "guest" })
    }.to change(BookingFolio, :count).by(1).and change(FolioOperationLog, :count).by(1)

    expect(@result).to be_success
    expect(@result.folio).not_to be_is_primary
    expect(@result.folio.name).to eq("Incidentals")
    expect(@result.folio.folio_sequence).to eq(3)
    expect(@result.folio.folio_reference_display).to eq("#{booking.reload.folio_account_reference_display}/3")
    expect(FolioOperationLog.last.operation_type).to eq("create_folio")
  end

  it "defaults new folios to external Company & Government payer with the selected account" do
    result = described_class.call(booking: booking, user: user, attributes: { hotel_corporate_account_id: hotel_corporate_account.id })

    expect(result).to be_success
    expect(result.folio.name).to eq("External Folio")
    expect(result.folio.folio_type).to eq("external")
    expect(result.folio.payer_type).to eq("company")
    expect(result.folio.hotel_corporate_account).to eq(hotel_corporate_account)
  end

  it "rejects Company & Government folios without a selected account" do
    result = described_class.call(booking: booking, user: user, attributes: {})

    expect(result).not_to be_success
    expect(result.error).to include("Company & Government")
  end

  it "rejects suspended Company & Government accounts" do
    hotel_corporate_account.update!(status: "suspended", suspended_at: Time.current)

    result = described_class.call(booking: booking, user: user, attributes: { hotel_corporate_account_id: hotel_corporate_account.id })

    expect(result).not_to be_success
    expect(result.error).to include("must be active")
  end

  it "rejects Company & Government accounts from another hotel" do
    other_relationship = create(:hotel_corporate_account)

    result = described_class.call(booking: booking, user: user, attributes: { hotel_corporate_account_id: other_relationship.id })

    expect(result).not_to be_success
    expect(result.error).to include("must belong to the folio hotel")
  end

  it "coerces locked guest and house payer types" do
    guest_result = described_class.call(booking: booking, user: user, attributes: { folio_type: "guest", payer_type: "company" })
    house_result = described_class.call(booking: booking, user: user, attributes: { folio_type: "house", payer_type: "custom" })

    expect(guest_result).to be_success
    expect(guest_result.folio.payer_type).to eq("guest")
    expect(house_result).to be_success
    expect(house_result.folio.payer_type).to eq("hotel")
  end

  it "does not change references when a new folio becomes primary" do
    original_account_reference = booking.reload.folio_account_reference_display
    original_guest_reference = guest_folio.reload.folio_reference_display

    result = described_class.call(
      booking: booking,
      user: user,
      attributes: {
        name: "Company Primary",
        folio_type: "external",
        payer_type: "company",
        hotel_corporate_account_id: hotel_corporate_account.id,
        is_primary: "1",
        set_folio_as_primary_reason: "Company pays"
      }
    )

    expect(result).to be_success
    expect(booking.reload.folio_account_reference_display).to eq(original_account_reference)
    expect(guest_folio.reload.folio_reference_display).to eq(original_guest_reference)
    expect(result.folio.reload).to be_is_primary
    expect(result.folio.folio_reference_display).to eq("#{original_account_reference}/3")
  end

  it "creates and promotes a room-scoped folio without disturbing other primary scopes" do
    group_booking = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group_booking, group_position: 1)
    sibling = create(:booking, hotel: hotel, group_booking: group_booking, group_position: 2)
    room = create(:booking_room, booking: booking)
    sibling_room = create(:booking_room, booking: sibling)
    old_room_primary = create(:booking_folio, booking: booking, hotel: hotel, booking_room: room, folio_number: 103)
    sibling_primary = create(:booking_folio, booking: sibling, hotel: hotel, booking_room: sibling_room, folio_number: 104)

    result = described_class.call(
      booking: booking,
      user: user,
      attributes: {
        booking_room_id: room.id,
        name: "Room Guest Folio",
        folio_type: "guest",
        payer_type: "guest",
        is_primary: true,
        set_folio_as_primary_reason: "Initialize room billing"
      }
    )

    expect(result).to be_success
    expect(group_booking.bookings.reload).to all(satisfy { |child| child.booking_rooms.one? })
    expect(result.folio.booking_room).to eq(room)
    expect(result.folio).to be_is_primary
    expect(guest_folio.reload).to be_is_primary
    expect(old_room_primary.reload).not_to be_is_primary
    expect(sibling_primary.reload).to be_is_primary
    expect(FolioOperationLog.last.metadata["booking_room_id"]).to eq(room.id)
  end

  it "rejects room scope from another booking" do
    other_room = create(:booking_room)

    result = described_class.call(
      booking: booking,
      user: user,
      attributes: {
        booking_room_id: other_room.id,
        name: "Invalid Room Folio",
        folio_type: "guest",
        payer_type: "guest"
      }
    )

    expect(result).not_to be_success
    expect(result.error).to include("Booking room must belong to the same booking")
  end
end
