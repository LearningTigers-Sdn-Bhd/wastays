# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ReinstateGroup, type: :service do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:group) { create(:group_booking, hotel: hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: %w[101 102 103]) }
  let(:first) { create(:booking, hotel: hotel, group_booking: group, status: "no_show") }
  let(:second) { create(:booking, hotel: hotel, group_booking: group, status: "no_show") }
  let!(:first_room) { create(:booking_room, booking: first, room_type: room_type, room_number: "101") }
  let!(:second_room) { create(:booking_room, booking: second, room_type: room_type, room_number: "102") }
  let(:attributes) do
    {
      first.id.to_s => { booking_rooms_attributes: [ { id: first_room.id, room_type_id: room_type.id, room_number: "101" } ] },
      second.id.to_s => { booking_rooms_attributes: [ { id: second_room.id, room_type_id: room_type.id, room_number: "102" } ] }
    }
  end
  let(:options) { { reason: "Late group arrival" } }

  subject(:result) do
    described_class.call(group_booking: group, booking_attributes: attributes, user: user, options: options)
  end

  it "reinstates every selected child" do
    allow(Bookings::ReinstateReservation).to receive(:new) do |booking:, **|
      instance_double(Bookings::ReinstateReservation, call: OpenStruct.new(success?: true, booking: booking))
    end

    expect(result).to be_success
    expect(result.bookings).to contain_exactly(first, second)
    expect(Bookings::ReinstateReservation).to have_received(:new).twice
  end

  it "rejects duplicate room assignments before changing any child" do
    attributes[second.id.to_s][:booking_rooms_attributes][0][:room_number] = "101"

    expect(result).not_to be_success
    expect(result.error).to include("same room")
  end

  it "rejects children outside the group" do
    outsider = create(:booking, hotel: hotel, status: "no_show")
    outsider_room = create(:booking_room, booking: outsider, room_type: room_type, room_number: "103")
    attributes[outsider.id.to_s] = { booking_rooms_attributes: [ { id: outsider_room.id, room_type_id: room_type.id, room_number: "103" } ] }

    expect(result).not_to be_success
    expect(result.error).to include("not part of this group")
  end

  it "rejects a child whose status changed after selection" do
    second.update_column(:status, "checked_in")

    expect(result).not_to be_success
    expect(result.error).to include("no longer eligible")
  end

  it "rolls back earlier children when a later reinstatement fails" do
    calls = 0
    allow(Bookings::ReinstateReservation).to receive(:new) do |booking:, **|
      calls += 1
      response = if calls == 1
        booking.update_column(:status, "checked_in")
        OpenStruct.new(success?: true)
      else
        OpenStruct.new(success?: false, error: "Room unavailable")
      end
      instance_double(Bookings::ReinstateReservation, call: response)
    end

    expect(result).not_to be_success
    expect(result.error).to eq("Room unavailable")
    expect(first.reload.status).to eq("no_show")
    expect(second.reload.status).to eq("no_show")
  end
end
