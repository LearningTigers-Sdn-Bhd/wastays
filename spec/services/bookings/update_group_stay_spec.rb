# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::UpdateGroupStay do
  it "requires at least one booking" do
    group = create(:group_booking)

    result = described_class.call(group_booking: group, booking_ids: [], params: {}, user: nil)

    expect(result).not_to be_success
    expect(result.error).to eq("Select at least one booking.")
  end

  it "rejects bookings outside the group" do
    group = create(:group_booking)
    outsider = create(:booking, hotel: group.hotel)

    result = described_class.call(group_booking: group, booking_ids: [ outsider.id ], params: {}, user: nil)

    expect(result).not_to be_success
    expect(result.error).to eq("One or more selected bookings are not part of this group.")
  end

  it "requires check-in and check-out dates" do
    group = create(:group_booking)
    booking = create(:booking, hotel: group.hotel, group_booking: group)

    result = described_class.call(group_booking: group, booking_ids: [ booking.id ], params: { check_in: Date.current }, user: nil)

    expect(result).not_to be_success
    expect(result.error).to eq("Check-in and check-out dates are required.")
  end

  it "rejects ineligible booking statuses" do
    group = create(:group_booking)
    booking = create(:booking, hotel: group.hotel, group_booking: group, status: "completed")

    result = described_class.call(group_booking: group, booking_ids: [ booking.id ], params: stay_params, user: nil)

    expect(result).not_to be_success
    expect(result.error).to eq("One or more selected bookings are no longer eligible for stay amendment.")
  end

  it "updates every selected group booking" do
    group = create(:group_booking)
    user = create(:user, account: group.hotel.account)
    first = create(:booking, hotel: group.hotel, group_booking: group, status: "confirmed")
    second = create(:booking, hotel: group.hotel, group_booking: group, status: "checked_in")
    first_service = instance_double(Bookings::UpdateStayService, call: OpenStruct.new(success?: true))
    second_service = instance_double(Bookings::UpdateStayService, call: OpenStruct.new(success?: true))
    allow(Bookings::UpdateStayService).to receive(:new).with(booking: first, params: stay_params, user: user).and_return(first_service)
    allow(Bookings::UpdateStayService).to receive(:new).with(booking: second, params: stay_params, user: user).and_return(second_service)

    result = described_class.call(group_booking: group, booking_ids: [ first.id, second.id ], params: stay_params, user: user)

    expect(result).to be_success
    expect(result.bookings).to match_array([ first, second ])
    expect(first_service).to have_received(:call)
    expect(second_service).to have_received(:call)
  end

  it "fails the batch when a child stay update fails" do
    group = create(:group_booking)
    first = create(:booking, hotel: group.hotel, group_booking: group, status: "confirmed")
    second = create(:booking, hotel: group.hotel, group_booking: group, status: "confirmed")
    allow(Bookings::UpdateStayService).to receive(:new).with(booking: first, params: stay_params, user: nil)
      .and_return(instance_double(Bookings::UpdateStayService, call: OpenStruct.new(success?: true)))
    allow(Bookings::UpdateStayService).to receive(:new).with(booking: second, params: stay_params, user: nil)
      .and_return(instance_double(Bookings::UpdateStayService, call: OpenStruct.new(success?: false, errors: [ "Room unavailable" ])))

    result = described_class.call(group_booking: group, booking_ids: [ first.id, second.id ], params: stay_params, user: nil)

    expect(result).not_to be_success
    expect(result.bookings).to eq([])
    expect(result.error).to eq("Room unavailable")
  end

  def stay_params
    { check_in: Date.current + 1.day, check_out: Date.current + 3.days }
  end
end
