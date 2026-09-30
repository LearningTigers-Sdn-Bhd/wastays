# frozen_string_literal: true

require "rails_helper"

RSpec.describe Boats::ResolveTimes do
  let(:hotel) { build(:hotel, time_zone: "Kuala Lumpur", allow_boat_information: true) }
  let(:check_in) { Time.utc(2026, 8, 1, 4, 0) }
  let(:check_out) { Time.utc(2026, 8, 4, 4, 0) }

  def resolve(params)
    described_class.call(hotel: hotel, check_in: check_in, check_out: check_out, params: params)
  end

  def local(value)
    value&.in_time_zone(hotel.hotel_time_zone)&.strftime("%Y-%m-%d %H:%M")
  end

  it "pairs boat-in with the check-in date and boat-out with the check-out date" do
    result = resolve(boat_in_time: "09:30", boat_out_time: "16:45")

    expect(local(result[:boat_in_at])).to eq("2026-08-01 09:30")
    expect(local(result[:boat_out_at])).to eq("2026-08-04 16:45")
  end

  it "ignores a submitted value that is not a usable time" do
    expect(resolve(boat_in_time: "custom")).to eq(boat_in_at: nil)
    expect(resolve(boat_in_time: "25:00")).to eq(boat_in_at: nil)
  end

  it "clears a slot submitted blank" do
    expect(resolve(boat_in_time: "")).to eq(boat_in_at: nil)
  end

  it "leaves a slot untouched when its field was not submitted" do
    expect(resolve(boat_out_time: "16:45")).not_to have_key(:boat_in_at)
    expect(resolve({})).to eq({})
  end

  it "resolves nothing when the property has boat information off" do
    hotel.allow_boat_information = false

    expect(resolve(boat_in_time: "09:30", boat_out_time: "16:45")).to eq({})
  end

  it "accepts request parameters as well as a plain hash" do
    params = ActionController::Parameters.new(boat_in_time: "09:30")

    expect(local(resolve(params)[:boat_in_at])).to eq("2026-08-01 09:30")
  end
end
