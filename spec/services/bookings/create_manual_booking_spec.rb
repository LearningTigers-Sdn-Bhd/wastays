# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CreateManualBooking do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 5, room_numbers: [ "101", "102", "103", "104", "105" ]) }
  let(:params) do
    {
      guest_name: "Test Guest",
      guest_email: "test@example.com",
      guest_phone: "123456",
      check_in: Date.current,
      check_out: Date.current + 1.day,
      room_type_id: room_type.id,
      room_number: "101",
      adults: 2
    }
  end

  subject { described_class.new(hotel: hotel, params: params) }

  it "creates a booking and deducts inventory" do
    dispatcher = instance_double(Notifications::Dispatcher, call: [])
    allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)

    expect {
      result = subject.call
      expect(result.success?).to be true
      expect(result.booking).to be_persisted
      expect(result.booking.hotel_snapshot["room_number"]).to eq("101")
    }.to have_enqueued_job(WebhookBroadcastJob).with('booking_confirmed', anything)

    inventory = room_type.room_inventories.find_by(date: Date.current)
    expect(inventory.quantity).to eq(4)
    expect(Notifications::Dispatcher).to have_received(:new).with(event: :booking_confirmed, booking: kind_of(Booking))
  end

  it "returns errors when booking fails" do
    params[:guest_name] = nil
    result = subject.call
    expect(result.success?).to be false
    expect(result.errors).to include("Guest name can't be blank")
  end

  it "allows a manually recorded partial payment" do
    params.merge!(
      record_payment: "1",
      payment_amount: "25.00",
      payment_method: "cash"
    )

    result = subject.call

    expect(result.success?).to be true
    expect(result.booking.payment_status).to eq("partial")
    expect(result.booking.payment_transactions.first.amount_subunits).to eq(2_500)
  end

  it "rejects non-positive manual payment amounts" do
    params.merge!(record_payment: "1", payment_amount: "0")

    result = subject.call

    expect(result.success?).to be false
    expect(result.errors).to include("Payment amount must be greater than 0.")
  end
end
