# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CreateStaffBooking do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 5, room_numbers: [ "101" ]) }
  let(:common_params) do
    {
      guest_name: "Reserved Guest", guest_email: "reserved@example.com", guest_phone: "123456",
      check_in: Date.current, check_out: Date.current + 1.day, adults: 1
    }
  end
  let(:room_rows) { [ { room_type_id: room_type.id, room_number: "" } ] }

  before do
    allow(Notifications::Dispatcher).to receive(:new).and_return(instance_double(Notifications::Dispatcher, call: []))
    create(:room_rate, room_type: room_type, date: Date.current, price: 200)
  end

  it "creates an unassigned reservation and deducts room-type inventory" do
    result = described_class.new(hotel: hotel, common_params: common_params, room_rows: room_rows, user: nil).call

    expect(result.success?).to be(true)
    expect(result.booking.booking_rooms.sole).to have_attributes(room_type: room_type, room_number: nil)
    expect(room_type.room_inventories.find_by!(date: Date.current).quantity).to eq(4)
  end

  it "requires a room number for walk-in creation" do
    result = described_class.new(
      hotel: hotel, common_params: common_params, room_rows: room_rows, user: nil, booking_type: "walk_in"
    ).call

    expect(result.success?).to be(false)
    expect(result.errors).to include("Each room row requires a room category and room number.")
  end

  it "uses a reservation-specific message when room category is missing" do
    result = described_class.new(
      hotel: hotel, common_params: common_params, room_rows: [ { room_type_id: "", room_number: "" } ], user: nil
    ).call

    expect(result.success?).to be(false)
    expect(result.errors).to include("Each reservation row requires a room category.")
  end

  it "rejects an unassigned reservation when its room type is sold out" do
    create(:room_inventory, room_type: room_type, date: Date.current, quantity: 0, status: "open")

    result = described_class.new(hotel: hotel, common_params: common_params, room_rows: room_rows, user: nil).call

    expect(result.success?).to be(false)
    expect(result.errors.join).to include("Not enough inventory for #{room_type.name}")
    expect(Booking.where(hotel: hotel)).to be_empty
  end

  it "sponsors room charges to the company without hijacking the guest folio" do
    corporate_account = create(:hotel_corporate_account, hotel: hotel)
    params = common_params.merge(hotel_corporate_account_id: corporate_account.id)

    result = described_class.new(hotel: hotel, common_params: params, room_rows: room_rows, user: nil).call
    expect(result.errors).to be_empty

    booking = result.booking
    guest_folio = booking.booking_folio
    company_folio = booking.booking_folios.find_by(payer_type: "company")

    # Guest primary folio stays guest-owned; the account id never leaks onto it.
    expect(guest_folio).to have_attributes(is_primary: true, payer_type: "guest", hotel_corporate_account_id: nil)

    # A separate external company folio carries the corporate account.
    expect(company_folio).to be_present
    expect(company_folio).to have_attributes(folio_type: "external", hotel_corporate_account_id: corporate_account.id)

    # Room revenue is *routed* to the company folio, not folio-hijacked.
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    rule = booking.folio_routing_rules.active.find_by(transaction_code: room_code)
    expect(rule&.target_folio_id).to eq(company_folio.id)

    # Accommodation forecasts land on the company folio; the guest folio has none.
    expect(company_folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation")).to be_present
    expect(guest_folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation")).to be_empty
  end

  it "rolls back all rooms when cumulative unassigned reservations exceed inventory" do
    room_type.update!(quantity: 1)
    create(:room_inventory, room_type: room_type, date: Date.current, quantity: 1, status: "open")
    rows = Array.new(2) { { room_type_id: room_type.id, room_number: "" } }

    result = described_class.new(hotel: hotel, common_params: common_params, room_rows: rows, user: nil).call

    expect(result.success?).to be(false)
    expect(Booking.where(hotel: hotel)).to be_empty
    expect(room_type.room_inventories.find_by!(date: Date.current).quantity).to eq(1)
  end
end
