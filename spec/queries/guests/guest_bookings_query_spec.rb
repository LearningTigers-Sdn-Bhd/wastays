# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::GuestBookingsQuery do
  let(:hotel) { create(:hotel) }
  let(:guest) { create(:guest, created_by_hotel: hotel) }

  it "returns an ordered relation without applying pagination" do
    check_out = Bookings::ScheduledStay.at_hotel_time(
      hotel: hotel,
      value: Date.new(2026, 7, 15),
      kind: :check_out
    )
    bookings = 2.times.map do
      booking = create(:booking, hotel: hotel, check_out: check_out)
      create(:booking_guest, booking: booking, guest: guest)
      booking
    end

    result = described_class.new(hotel: hotel, guest: guest).bookings

    expect(result).to be_an(ActiveRecord::Relation)
    expect(result.map(&:id)).to eq(bookings.reverse.map(&:id))
    expect(result).not_to respond_to(:total_pages)
  end
end
