require "rails_helper"

RSpec.describe Concierge::SelfCheckIn do
  let(:hotel) { create(:hotel, status: "live") }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    b = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.today, check_out: Date.today + 1)
    b.booking_rooms.create!(room_type: room_type, quantity: 1, subtotal: 200,
                             room_type_snapshot: { "name" => room_type.name })
    b
  end

  def with_available_room(room_number: "101")
    create(:room_inventory, room_type: room_type, date: Date.today,
           quantity: 1, status: "open", available_room_numbers: [ room_number ])
    room_number
  end

  def call
    described_class.new(booking: booking).call
  end

  context "when everything is ready" do
    before { with_available_room }

    it "checks in the booking" do
      result = call
      expect(result.success?).to be true
      expect(booking.reload.status).to eq("checked_in")
    end

    it "assigns the room number" do
      result = call
      expect(result.room_number).to eq("101")
      expect(booking.booking_rooms.first.reload.room_number).to eq("101")
    end
  end

  context "wrong date" do
    let(:booking) do
      b = create(:booking, hotel: hotel, status: "confirmed",
                 check_in: Date.tomorrow, check_out: Date.tomorrow + 1)
      b.booking_rooms.create!(room_type: room_type, quantity: 1, subtotal: 200,
                               room_type_snapshot: { "name" => room_type.name })
      b
    end

    it "returns :wrong_date" do
      result = call
      expect(result.success?).to be false
      expect(result.error_code).to eq(:wrong_date)
    end
  end

  context "too early" do
    before do
      future_time = (Time.current + 2.hours).strftime("%H:%M")
      hotel.create_property_policy!(check_in_time: future_time, check_out_time: "12:00",
                                    currency: "MYR") unless hotel.property_policy
      hotel.property_policy.update!(check_in_time: future_time)
      with_available_room
    end

    it "returns :too_early" do
      result = call
      expect(result.success?).to be false
      expect(result.error_code).to eq(:too_early)
    end
  end

  context "no room available" do
    it "returns :no_room_available when no inventory" do
      result = call
      expect(result.error_code).to eq(:no_room_available)
    end

    it "returns :no_room_available when available_room_numbers is empty" do
      create(:room_inventory, room_type: room_type, date: Date.today,
             quantity: 1, status: "open", available_room_numbers: [])
      result = call
      expect(result.error_code).to eq(:no_room_available)
    end

    it "returns :no_room_available when all rooms are not ready" do
      with_available_room(room_number: "101")
      RoomStatus.create!(hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")
      result = call
      expect(result.error_code).to eq(:no_room_available)
    end
  end

  context "late arrival (past check_in date)" do
    let(:booking) do
      b = create(:booking, hotel: hotel, status: "confirmed",
                 check_in: Date.yesterday, check_out: Date.today)
      b.booking_rooms.create!(room_type: room_type, quantity: 1, subtotal: 200,
                               room_type_snapshot: { "name" => room_type.name })
      b
    end

    before { with_available_room }

    it "allows check-in" do
      result = call
      expect(result.success?).to be true
    end
  end

  context "no check_in_time configured" do
    before do
      hotel.property_policy&.update!(check_in_time: nil)
      with_available_room
    end

    it "skips time check and allows check-in" do
      result = call
      expect(result.success?).to be true
    end
  end

  context "when room assignment fails inside the transaction" do
    before do
      with_available_room

      failed_assignment = Struct.new(:success?, :error, keyword_init: true).new(
        success?: false,
        error: "Assignment failed"
      )
      allow_any_instance_of(Bookings::AssignRoom).to receive(:call).and_return(failed_assignment)
    end

    it "returns a failure result and leaves the booking unchanged" do
      result = call

      expect(result.success?).to be false
      expect(result.error_code).to eq(:error)
      expect(booking.reload.status).to eq("confirmed")
    end
  end
end
