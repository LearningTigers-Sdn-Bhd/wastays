# frozen_string_literal: true

require "rails_helper"

RSpec.describe BoatSchedules::BulkUpdate do
  let(:hotel) { create(:hotel) }
  let(:slot_a) { create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "09:30", has_breakfast: true, has_lunch: false) }
  let(:slot_b) { create(:hotel_boat_schedule, hotel: hotel, kind: "boat_out", time: "18:00", has_dinner: false) }

  it "does nothing and reports zero updates when nothing changed" do
    result = described_class.call(hotel: hotel, attributes: {})

    expect(result).to be_success
    expect(result.updated_count).to eq(0)
  end

  it "updates every slot in the batch" do
    result = described_class.call(
      hotel: hotel,
      attributes: {
        slot_a.id.to_s => { "time" => "09:45", "has_lunch" => "1" },
        slot_b.id.to_s => { "has_dinner" => "1" }
      }
    )

    expect(result).to be_success
    expect(result.updated_count).to eq(2)
    expect(slot_a.reload.time_of_day).to eq("09:45")
    expect(slot_a.has_lunch).to eq(true)
    expect(slot_b.reload.has_dinner).to eq(true)
  end

  it "saves none of the batch when one slot fails validation" do
    result = described_class.call(
      hotel: hotel,
      attributes: {
        slot_a.id.to_s => { "time" => "10:00" },
        slot_b.id.to_s => { "time" => "" }
      }
    )

    expect(result).not_to be_success
    expect(result.error).to be_present
    expect(slot_a.reload.time_of_day).to eq("09:30")
  end

  it "refuses a slot id that doesn't belong to this hotel" do
    other_slot = create(:hotel_boat_schedule, kind: "boat_in", time: "09:30")

    result = described_class.call(hotel: hotel, attributes: { other_slot.id.to_s => { "time" => "10:00" } })

    expect(result).not_to be_success
    expect(other_slot.reload.time_of_day).to eq("09:30")
  end
end
