# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelBoatSetting do
  it "writes hi-tea with its hyphen" do
    expect(described_class.meal_label(:hi_tea)).to eq("Hi-Tea")
    expect(described_class.meal_label("breakfast")).to eq("Breakfast")
  end

  it "requires hi-tea to fall between lunch and dinner" do
    setting = build(:hotel_boat_setting, lunch_time: "12:00", hi_tea_time: "20:00", dinner_time: "19:00")

    expect(setting).not_to be_valid
    expect(setting.errors[:base]).to include("Meal times must run breakfast, then lunch, then hi-tea, then dinner")

    setting.hi_tea_time = "15:30"
    expect(setting).to be_valid
  end

  it "pre-ticks hi-tea for an arrival before its service time" do
    setting = build(:hotel_boat_setting, hi_tea_time: "15:30")

    expect(setting.meals_for(Time.zone.parse("14:00"), "boat_in")).to include(hi_tea: true, lunch: false, dinner: true)
    expect(setting.meals_for(Time.zone.parse("16:00"), "boat_out")).to include(hi_tea: true, dinner: false)
  end

  it "never pre-ticks hi-tea while the property has no hi-tea time" do
    setting = build(:hotel_boat_setting, hi_tea_time: nil)

    expect(setting.meals_for(Time.zone.parse("09:00"), "boat_in")).to include(hi_tea: false)
  end
end
