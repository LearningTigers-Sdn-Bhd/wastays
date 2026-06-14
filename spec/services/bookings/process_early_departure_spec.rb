# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ProcessEarlyDeparture do
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }

  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 10) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", check_in: Date.current, check_out: Date.current + 3.days) }
  let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, quantity: 1) }
  let(:folio) { Folios::InitializeForBooking.call(booking: booking, user: user) }

  before do
    # Ensure folio is initialized and settled (or we test the settlement logic)
    # For simplicity in this unit test, let's assume it's already settled or we don't care about the balance yet.
    allow_any_instance_of(Folios::CloseForCheckout).to receive(:call).and_return(OpenStruct.new(success?: true, folio: folio))
  end

  it "truncates the check_out date and completes checkout" do
    result = described_class.call(booking: booking, user: user, params: { apply_charge: "false" })

    expect(result).to be_success
    expect(booking.reload.check_out.to_date).to eq(Date.current)
    expect(booking.status).to eq("completed")
  end

  it "posts a charge if requested" do
    result = described_class.call(
      booking: booking,
      user: user,
      params: { apply_charge: "true", charge_amount: "150.0" }
    )

    expect(result).to be_success
    expect(booking.reload.status).to eq("completed")
    expect(folio.folio_transactions.charge.find_by(description: "Early Departure Charge").amount).to eq(150.0)
  end

  it "fails if charge amount is invalid" do
    result = described_class.call(
      booking: booking,
      user: user,
      params: { apply_charge: "true", charge_amount: "-10" }
    )

    expect(result).not_to be_success
    expect(result.error).to include("Charge amount must be greater than zero")
    expect(booking.reload.status).to eq("checked_in")
  end

  it "fails if booking is not checked in" do
    confirmed = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current, check_out: Date.current + 3.days)
    result = described_class.call(booking: confirmed, user: user)

    expect(result).not_to be_success
    expect(result.error).to eq("Booking is not checked in.")
  end

  it "releases inventory for unused future nights" do
    future_date = Date.current + 1.day
    final_unused_date = Date.current + 2.days
    create(:room_inventory, room_type: room_type, date: Date.current, quantity: 9)
    create(:room_inventory, room_type: room_type, date: future_date, quantity: 9)
    create(:room_inventory, room_type: room_type, date: final_unused_date, quantity: 9)

    allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(future_date)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: future_date)

    result = described_class.call(booking: booking, user: user, params: { apply_charge: "false" })

    expect(result).to be_success
    expect(room_type.room_inventories.find_by(date: Date.current).quantity).to eq(9)
    expect(room_type.room_inventories.find_by(date: future_date).quantity).to eq(10)
    expect(room_type.room_inventories.find_by(date: final_unused_date).quantity).to eq(10)
  end

  it "uses the checkout timestamp to resolve the early departure business date" do
    timestamp = Time.current.change(hour: 1, min: 30)
    business_date = Date.current + 1.day
    allow_any_instance_of(Hotel).to receive(:business_date_for) do |_hotel, resolved_timestamp = nil|
      resolved_timestamp == timestamp ? business_date : Date.current
    end
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

    result = described_class.call(
      booking: booking,
      user: user,
      params: { apply_charge: "false" },
      options: { timestamp: timestamp }
    )

    expect(result).to be_success
    expect(booking.reload.check_out.to_date).to eq(business_date)
  end

  it "fails when the resolved departure date does not shorten the stay" do
    allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(booking.check_out.to_date)

    result = described_class.call(booking: booking, user: user, params: { apply_charge: "false" })

    expect(result).not_to be_success
    expect(result.error).to eq("Booking is not eligible for early departure.")
    expect(booking.reload.status).to eq("checked_in")
  end

  it "can defer final checkout after truncating the stay" do
    result = described_class.call(
      booking: booking,
      user: user,
      params: { apply_charge: "false" },
      options: { defer_checkout: true }
    )

    expect(result).to be_success
    expect(booking.reload.check_out.to_date).to eq(Date.current)
    expect(booking.status).to eq("checked_in")
  end
end
