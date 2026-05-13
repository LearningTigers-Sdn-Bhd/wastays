# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::UpdateStayService do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 10) }
  let(:booking) { create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 1.day) }
  let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, quantity: 1) }

  before do
    Bookings::InventoryManager.new(booking).deduct
  end

  it "updates dates and resyncs inventory" do
    params = { check_in: Date.current + 1.day, check_out: Date.current + 2.days }
    result = described_class.new(booking: booking, params: params).call

    expect(result.success?).to be true
    expect(room_type.room_inventories.find_by(date: Date.current).quantity).to eq(10)
    expect(room_type.room_inventories.find_by(date: Date.current + 1.day).quantity).to eq(9)
  end

  it "dispatches booking_updated when stay dates are changed" do
    dispatcher = instance_double(Notifications::Dispatcher, call: [])
    allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)

    params = { check_in: Date.current + 1.day, check_out: Date.current + 2.days }
    described_class.new(booking: booking, params: params).call

    expect(Notifications::Dispatcher).to have_received(:new).with(event: :booking_updated, booking: booking)
    expect(dispatcher).to have_received(:call)
  end

  it "does not dispatch booking_updated when dates are unchanged" do
    allow(Notifications::Dispatcher).to receive(:new)

    params = { guest_name: "Updated Name" }
    described_class.new(booking: booking, params: params).call

    expect(Notifications::Dispatcher).not_to have_received(:new)
  end

  it "updates room type and resyncs inventory" do
    new_room_type = create(:room_type, hotel: hotel, quantity: 5)
    params = { room_type_id: new_room_type.id }

    result = described_class.new(booking: booking, params: params).call

    expect(result.success?).to be true
    expect(room_type.room_inventories.find_by(date: Date.current).quantity).to eq(10)
    expect(new_room_type.room_inventories.find_by(date: Date.current).quantity).to eq(4)
  end

  it "creates a BookingAuditLog on update" do
    user = create(:user, account: hotel.account)
    old_name = booking.guest_name
    params = { guest_name: "New Guest Name" }

    expect {
      described_class.new(booking: booking, params: params, user: user).call
    }.to change(BookingAuditLog, :count).by(1)

    log = BookingAuditLog.last
    expect(log.auditable).to eq(booking)
    expect(log.user).to eq(user)
    expect(log.action_type).to eq("update")
    expect(log.old_value["guest_name"]).to eq(old_name)
    expect(log.new_value["guest_name"]).to eq("New Guest Name")
  end
end
