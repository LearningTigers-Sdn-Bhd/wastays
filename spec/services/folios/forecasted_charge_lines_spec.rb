# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::ForecastedChargeLines do
  it "returns accommodation and tax lines for each stay night" do
    booking = create(
      :booking,
      check_in: Date.current,
      check_out: Date.current + 2.days,
      tax_posting_snapshot: {
        Date.current.iso8601 => [ { "name" => "SST", "amount" => "6.00", "type" => "sst" } ],
        (Date.current + 1.day).iso8601 => [ { "name" => "SST", "amount" => "6.00", "type" => "sst" } ]
      }
    )
    booking_room = create(:booking_room, booking: booking, subtotal: 200)

    lines = described_class.call(booking: booking)

    expect(lines).to include(
      hash_including(stay_date: Date.current, charge_kind: "accommodation", identity: booking_room.id.to_s, amount: 100.to_d),
      hash_including(stay_date: Date.current, charge_kind: "tax", amount: 6.to_d)
    )
    expect(lines.size).to eq(4)
  end
end
