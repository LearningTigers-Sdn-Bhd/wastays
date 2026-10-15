# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260930010000_add_boat_types_to_booking_guests")

RSpec.describe AddBoatTypesToBookingGuests do
  it "backfills each existing timestamp independently and leaves blank transfers blank" do
    booking = create(:booking)
    guest = create(:booking_guest, booking: booking, boat_in_at: booking.check_in)
    outgoing_booking = create(:booking)
    outgoing = create(:booking_guest, booking: outgoing_booking, boat_out_at: outgoing_booking.check_out)
    blank = create(:booking_guest, booking: create(:booking))

    %w[in out].each { |direction| described_class.new.send(:backfill_type, direction) }

    expect(guest.reload).to have_attributes(boat_in_type: "provided", boat_out_type: nil)
    expect(guest.boat_in_at).to eq(booking.check_in)
    expect(outgoing.reload).to have_attributes(boat_in_type: nil, boat_out_type: "provided")
    expect(blank.reload).to have_attributes(boat_in_type: nil, boat_out_type: nil)
  end
end
