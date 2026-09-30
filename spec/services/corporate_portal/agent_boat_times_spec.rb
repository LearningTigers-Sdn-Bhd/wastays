# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::AgentBoatTimes do
  let(:hotel) { create(:hotel, allow_boat_information: true) }

  before do
    create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "09:00")
    create(:hotel_boat_schedule, hotel: hotel, kind: "boat_out", time: "10:00")
    create(:hotel_boat_schedule, :archived, hotel: hotel, kind: "boat_in", time: "07:00")
  end

  it "passes through only the boat fields that were sent" do
    boat = described_class.new(hotel: hotel, params: { "boat_in_time" => "09:00", "name" => "x" })

    expect(boat.params).to eq(boat_in_time: "09:00")
    expect(boat.errors).to be_empty
  end

  it "treats a blank as clearing the time, not as an error" do
    boat = described_class.new(hotel: hotel, params: { boat_in_time: "", boat_out_time: "10:00" })

    expect(boat.params).to eq(boat_in_time: "", boat_out_time: "10:00")
    expect(boat.errors).to be_empty
  end

  it "refuses a retired or unknown slot" do
    boat = described_class.new(hotel: hotel, params: { boat_in_time: "07:00", boat_out_time: "23:00" })

    expect(boat.errors).to eq([
      "Choose a boat-in time from the hotel's boat timetable.",
      "Choose a boat-out time from the hotel's boat timetable."
    ])
  end

  it "ignores boat fields at a hotel without boat information" do
    hotel.update!(allow_boat_information: false)
    boat = described_class.new(hotel: hotel, params: { boat_in_time: "07:00" })

    expect(boat.params).to be_empty
    expect(boat.errors).to be_empty
  end
  it "allows custom transfers without hotel schedule slots" do
    hotel.hotel_boat_schedules.delete_all
    boat = described_class.new(hotel: hotel, params: { boat_in_time: "charter", boat_in_custom_time: "18:03", boat_out_time: "own" })
    expect(boat.params).to include(boat_in_custom_time: "18:03")
    expect(boat.errors).to be_empty
  end

  it "validates custom times through the shared boat rules" do
    boat = described_class.new(hotel: hotel, params: { boat_in_time: "charter", boat_out_time: "own", boat_out_custom_time: "25:00" })
    expect(boat.errors).to contain_exactly("Enter a boat-in time for Charter Boat.", "Enter a valid boat-out time.")
  end
end
