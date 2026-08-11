# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::Financials::ComparePmsRate do
  it "totals nightly PMS rates using captured occupancy and reports the variance" do
    room_type = double(standard_rate_plan: :standard)
    room = double(room_type:, rate_plan: nil, occupancy_snapshot: { "adults" => 3, "children" => 1 })
    booking = double(
      booking_rooms: [ room ], check_in: Date.new(2026, 8, 11), check_out: Date.new(2026, 8, 13),
      currency: "MYR", adults: 2
    )
    allow(Rates::ResolveEffectiveNightlyPrice).to receive(:call).and_return(
      double(amount: 100.125.to_d), double(amount: 99.875.to_d)
    )

    result = described_class.call(bookings: [ booking ], accommodation_amount: 202)

    expect(Rates::ResolveEffectiveNightlyPrice).to have_received(:call).twice.with(
      room_type:, rate_plan: :standard, date: kind_of(Date), currency: "MYR", adults: 3, children: 1
    )
    expect(result).to have_attributes(
      expected_amount: 200.to_d, variance_amount: 2.to_d, variance_percentage: 1.to_d,
      reason: "fx_round_trip", room_nights: 2
    )
  end

  it "stops comparison when a nightly PMS rate cannot be resolved" do
    room = double(room_type: double(standard_rate_plan: :standard), rate_plan: nil, occupancy_snapshot: {})
    booking = double(
      booking_rooms: [ room ], check_in: Date.new(2026, 8, 11), check_out: Date.new(2026, 8, 13),
      currency: "MYR", adults: 2
    )
    allow(Rates::ResolveEffectiveNightlyPrice).to receive(:call).and_return(double(amount: nil))

    result = described_class.call(bookings: [ booking ], accommodation_amount: 100)

    expect(result).to have_attributes(
      expected_amount: nil, variance_amount: nil, variance_percentage: nil, reason: nil, room_nights: 1
    )
    expect(Rates::ResolveEffectiveNightlyPrice).to have_received(:call).once.with(
      hash_including(adults: 2, children: 0)
    )
  end
end
