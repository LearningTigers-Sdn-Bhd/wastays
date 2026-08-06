# frozen_string_literal: true

require "rails_helper"

RSpec.describe FrozenTimeHelpers do
  it "freezes an example through metadata", frozen_time: Time.utc(2026, 8, 15, 12, 30) do
    expect(Time.current).to eq(Time.utc(2026, 8, 15, 12, 30))
  end

  it "pins business-day examples to noon", frozen_time: :business_day do
    expect(Time.current).to eq(Time.current.change(hour: 12, min: 0, sec: 0, usec: 0))
  end

  it "restores time after a scoped freeze" do
    actual_time = Time.current

    with_frozen_time(Time.utc(2026, 8, 15, 12, 30)) do
      expect(Time.current).to eq(Time.utc(2026, 8, 15, 12, 30))
    end

    expect(Time.current).to be_within(1.second).of(actual_time)
  end
end
