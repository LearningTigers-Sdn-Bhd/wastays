# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CalculateStayPrice do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, base_price: 100) }
  let(:check_in) { Date.current }
  let(:check_out) { Date.current + 2.days }

  subject { described_class.new(room_type: room_type, check_in: check_in, check_out: check_out) }

  it "calculates total price using base price when no rates exist" do
    expect(subject.call).to eq(200) # 100 * 2 nights
  end

  it "uses custom rates when they exist" do
    create(:room_rate, room_type: room_type, date: check_in, price: 150)
    expect(subject.call).to eq(250) # 150 (night 1) + 100 (night 2)
  end

  it "returns 0 if room_type is nil" do
    service = described_class.new(room_type: nil, check_in: check_in, check_out: check_out)
    expect(service.call).to eq(0)
  end

  it "returns 0 if check_in is nil" do
    service = described_class.new(room_type: room_type, check_in: nil, check_out: check_out)
    expect(service.call).to eq(0)
  end
end
