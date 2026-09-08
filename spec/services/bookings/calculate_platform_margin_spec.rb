# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CalculatePlatformMargin do
  it "calculates a two-decimal commission from the room subtotal" do
    hotel = create(:hotel)
    create(:margin_rule, settable: hotel, rate: 10)

    result = described_class.call(hotel: hotel, room_total: 100)

    expect(result.rate).to eq(10.to_d)
    expect(result.amount).to eq(10.to_d)
  end

  it "uses the hotel rate before the global rate" do
    hotel = create(:hotel)
    create(:margin_rule, rate: 15)
    create(:margin_rule, settable: hotel, rate: 8.5)

    result = described_class.call(hotel: hotel, room_total: 123.45)

    expect(result.rate).to eq(8.5.to_d)
    expect(result.amount).to eq(10.49.to_d)
  end
end
