# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::NextFolioNumber do
  let(:hotel) { create(:hotel) }

  it "issues the next value off the counter when it is not behind" do
    HotelCounter.create!(hotel: hotel, counter_type: "folio", last_value: 40)

    expect(described_class.call(hotel: hotel)).to eq(41)
  end

  it "never reissues a number when the counter has drifted behind existing folios" do
    booking = create(:booking, hotel: hotel)
    create(:booking_folio, booking: booking, folio_number: 267)
    # Counter left behind the real max, as a snapshot / seed import would.
    HotelCounter.create!(hotel: hotel, counter_type: "folio", last_value: 262)

    issued = described_class.call(hotel: hotel)

    expect(issued).to eq(268)
    expect(BookingFolio.where(hotel_id: hotel.id, folio_number: issued)).not_to exist
  end

  it "self-heals the counter so the following call runs straight off it" do
    booking = create(:booking, hotel: hotel)
    create(:booking_folio, booking: booking, folio_number: 100)
    HotelCounter.create!(hotel: hotel, counter_type: "folio", last_value: 5)

    expect(described_class.call(hotel: hotel)).to eq(101)
    expect(HotelCounter.find_by(hotel: hotel, counter_type: "folio").last_value).to eq(101)
    expect(described_class.call(hotel: hotel)).to eq(102)
  end

  it "is scoped per hotel" do
    other = create(:hotel)
    other_booking = create(:booking, hotel: other)
    create(:booking_folio, booking: other_booking, folio_number: 999)

    expect(described_class.call(hotel: hotel)).to eq(1)
  end
end
