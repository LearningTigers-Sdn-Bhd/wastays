# frozen_string_literal: true

require "rails_helper"

# Date changes go through UpdateStayService; these cover the pricing it saves.
RSpec.describe Bookings::CarryStayRates do
  let(:hotel) { create(:hotel, sst_enabled: true) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 10) }
  let(:rate_plan) { room_type.standard_rate_plan }
  let(:arrival) { Date.current + 1.day }
  let(:booking) do
    create(:booking, hotel: hotel,
      check_in: Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: arrival, kind: :check_in),
      check_out: Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: arrival + 2.days, kind: :check_out))
  end
  let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan) }

  before do
    (arrival - 2.days..arrival + 6.days).each { |date| create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: date, price: 150.0) }
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
  end

  def price_stay(nightly_prices, **booking_attributes)
    snapshot = nightly_prices.each_with_index.to_h do |price, index|
      date = (arrival + index).iso8601
      [ date, { "date" => date, "price" => price.to_s, "currency" => "MYR", "rate_plan_id" => rate_plan.id, "source" => "manual_override" } ]
    end
    booking_room.update!(nightly_rate_snapshot: snapshot, subtotal: nightly_prices.sum)
    booking.update!(booking_attributes) if booking_attributes.any?
  end

  def move_stay(check_in:, check_out:)
    result = Bookings::UpdateStayService.new(booking: booking, params: { check_in:, check_out: }).call
    expect(result.success?).to be(true), -> { Array(result.errors).to_sentence }
    booking.reload
  end

  def nightly_prices
    booking_room.reload.nightly_rate_snapshot.sort.map { |_date, entry| entry["price"].to_d }
  end

  it "extends a hand-priced stay at its own nightly rate, not the room rate" do
    price_stay([ 98, 98 ], manual_rate_override: 196)

    move_stay(check_in: arrival, check_out: arrival + 3.days)

    expect(nightly_prices).to eq([ 98, 98, 98 ])
    expect(booking_room.subtotal).to eq(294)
    expect(booking.manual_rate_override).to eq(294)
    expect(Booking.non_tourism_tax_total_for(booking.tax_lines)).to eq(23.52.to_d)
    expect(booking.total_amount).to eq(317.52.to_d)
    expect(booking.tax_posting_snapshot.keys).to eq([ arrival, arrival + 1, arrival + 2 ].map(&:iso8601))
  end

  it "keeps each retained night's price and copies the nearest night into added ones" do
    price_stay([ 90, 110 ], manual_rate_override: 200)

    move_stay(check_in: arrival - 1.day, check_out: arrival + 4.days)

    expect(nightly_prices).to eq([ 90, 90, 110, 110, 110 ])
    added = booking_room.nightly_rate_snapshot.fetch((arrival + 2).iso8601)
    expect(added).to include("source" => described_class::SOURCE, "carried_from" => (arrival + 1).iso8601)
    expect(booking.manual_rate_override).to eq(510)
  end

  it "shortens a hand-priced stay without re-spreading the old total" do
    price_stay([ 90, 110 ], manual_rate_override: 200)

    move_stay(check_in: arrival + 1.day, check_out: arrival + 2.days)

    expect(nightly_prices).to eq([ 110 ])
    expect(booking.manual_rate_override).to eq(110)
  end

  it "keeps the nightly prices in order when the stay moves to new dates" do
    price_stay([ 90, 110 ], manual_rate_override: 200)

    move_stay(check_in: arrival + 4.days, check_out: arrival + 6.days)

    expect(nightly_prices).to eq([ 90, 110 ])
    expect(booking.manual_rate_override).to eq(200)
  end

  it "splits a legacy override evenly when the stay has no nightly snapshot" do
    booking.update!(manual_rate_override: 196)

    move_stay(check_in: arrival, check_out: arrival + 3.days)

    expect(nightly_prices).to eq([ 98, 98, 98 ])
    expect(booking.manual_rate_override).to eq(294)
  end

  it "extends an OTA stay at the OTA price without inventing an override" do
    price_stay([ 120, 120 ], source: "ota")

    move_stay(check_in: arrival, check_out: arrival + 3.days)

    expect(nightly_prices).to eq([ 120, 120, 120 ])
    expect(booking.manual_rate_override).to be_nil
  end

  it "still prices a rack-rate stay from the room rates" do
    price_stay([ 150, 150 ])

    move_stay(check_in: arrival, check_out: arrival + 3.days)

    expect(nightly_prices).to eq([ 150, 150, 150 ])
    expect(booking.manual_rate_override).to be_nil
  end
end
