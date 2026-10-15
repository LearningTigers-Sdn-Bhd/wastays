# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::CreateCancelledBooking do
  let(:hotel) { create(:hotel, status: "live", country: "Malaysia") }
  let(:user) { create(:user, account: hotel.account) }
  let!(:room_type) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Deluxe", room_number_mode: "custom", quantity: 2, base_price: 250.0,
                    max_adults: 3, max_children: 2, room_numbers: %w[101 102] }
    )
  end

  def params(overrides = {})
    {
      guest_name: "Moon Lee", guest_phone: "NOT CAPTURED RES1-1", adults: 2, children: 0,
      check_in: Date.current + 10, check_out: Date.current + 12, room_type_id: room_type.id,
      room_number: "101", require_room_number: false, source: "travel_agent", external_reference: "RES1-1",
      manual_rate_override: 500, internal_notes: "Imported."
    }.merge(overrides)
  end

  def call(overrides = {}) = described_class.new(hotel: hotel, params: params(overrides), user: user).call

  it "records the reservation as a cancelled booking" do
    result = call

    expect(result).to be_success
    expect(result.booking).to have_attributes(status: "cancelled", external_reference: "RES1-1", source: "travel_agent", guest_name: "Moon Lee")
  end

  it "keeps the price the source stated" do
    expect(call.booking.total_amount.to_d).to eq(500)
  end

  it "keeps the guest, so staff can see their past bookings, cancelled ones included" do
    booking = call.booking

    expect(booking.primary_guest).to have_attributes(name: "Moon Lee", created_by_hotel_id: hotel.id)
  end

  it "gives every released reservation its own guest" do
    first = call(guest_phone: "NOT CAPTURED RES1-1").booking
    second = call(guest_phone: "NOT CAPTURED RES1-2", external_reference: "RES1-2").booking

    expect(first.primary_guest).not_to eq(second.primary_guest)
  end

  it "holds no room: none is assigned and no inventory is taken" do
    expect { call }.not_to change { RoomInventory.where(room_type_id: room_type.id).sum(:quantity) }

    expect(call(external_reference: "RES1-3").booking.booking_rooms.first.room_number).to be_blank
  end

  it "accepts a stay in the past, which a live booking would not" do
    result = call(check_in: Date.current - 40, check_out: Date.current - 38)

    expect(result).to be_success
    expect(result.booking.check_in.to_date).to eq(Date.current - 40)
  end

  it "opens no folio and charges no tourism tax" do
    booking = call.booking

    expect(booking.tourism_tax_amount).to eq(0)
    expect(booking.booking_folios).to be_empty
  end

  it "writes an audit entry for the creation, marked as released in the source system" do
    booking = call.booking

    log = BookingAuditLog.where(auditable: booking).order(:id).last
    expect(log.metadata).to include("imported_as" => "cancelled")
  end

  it "reports a category that does not exist, instead of raising" do
    result = call(room_type_id: 0)

    expect(result).not_to be_success
    expect(result.errors).to be_present
  end
end
