# frozen_string_literal: true

require "rails_helper"

RSpec.describe Boats::AssignTimes do
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur", allow_boat_information: true) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      check_in: Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: Date.new(2026, 8, 1), kind: :check_in),
      check_out: Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: Date.new(2026, 8, 4), kind: :check_out))
  end
  let!(:primary) { create(:booking_guest, booking: booking, is_primary: true) }

  def local(value)
    value&.in_time_zone(hotel.hotel_time_zone)&.strftime("%Y-%m-%d %H:%M")
  end

  it "writes the resolved slots onto the primary guest" do
    described_class.call(booking: booking, params: { boat_in_time: "09:30", boat_out_time: "16:45" })

    expect(local(primary.reload.boat_in_at)).to eq("2026-08-01 09:30")
    expect(local(primary.boat_out_at)).to eq("2026-08-04 16:45")
  end

  it "clears a slot submitted blank" do
    described_class.call(booking: booking, params: { boat_in_time: "09:30" })
    described_class.call(booking: booking, params: { boat_in_time: "" })

    expect(primary.reload.boat_in_at).to be_nil
  end

  it "leaves the guest untouched when the form submitted no boat fields" do
    expect { described_class.call(booking: booking, params: { adults: 2 }) }
      .not_to change { primary.reload.updated_at }
  end

  it "does nothing when the property has boat information off" do
    hotel.update!(allow_boat_information: false)

    described_class.call(booking: booking, params: { boat_in_time: "09:30" })

    expect(primary.reload.boat_in_at).to be_nil
  end

  it "falls back to the first guest when no guest is marked primary" do
    primary.update!(is_primary: false)
    additional = booking.booking_guests.first

    described_class.call(booking: booking, params: { boat_in_time: "09:30" })

    expect(local(additional.reload.boat_in_at)).to eq("2026-08-01 09:30")
  end

  it "does not raise when the booking has no guests" do
    guestless = create(:booking, hotel: hotel)

    expect { described_class.call(booking: guestless, params: { boat_in_time: "09:30" }) }.not_to raise_error
  end
  before do
    create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "09:30")
    create(:hotel_boat_schedule, hotel: hotel, kind: "boat_out", time: "16:45")
  end

  it "clears a stale time when switching to untimed Own Boat" do
    described_class.call(booking: booking, params: { boat_in_time: "09:30" })
    described_class.call(booking: booking, params: { boat_in_time: "own" })
    expect(primary.reload).to have_attributes(boat_in_type: "own", boat_in_at: nil)
  end

  it "pairs shared group selections with each booking's own stay dates" do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    later = create(:booking, hotel: hotel, group_booking: group, group_position: 2,
      check_in: booking.check_in + 2.days, check_out: booking.check_out + 2.days)
    later_guest = create(:booking_guest, booking: later, is_primary: true)
    [ booking, later ].each do |record|
      described_class.call(booking: record, params: { boat_in_time: "charter", boat_in_custom_time: "18:03", boat_out_time: "own", boat_out_custom_time: "17:12" })
    end
    expect(local(primary.reload.boat_in_at)).to eq("2026-08-01 18:03")
    expect(local(later_guest.reload.boat_in_at)).to eq("2026-08-03 18:03")
    expect(local(primary.boat_out_at)).to eq("2026-08-04 17:12")
    expect(local(later_guest.boat_out_at)).to eq("2026-08-06 17:12")
  end
end
