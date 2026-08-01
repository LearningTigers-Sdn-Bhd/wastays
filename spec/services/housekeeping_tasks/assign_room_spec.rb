# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::AssignRoom do
  it "uses the shared room-operation authorization and room lookup contract" do
    expect(described_class.superclass).to eq(HousekeepingTasks::RoomOperation)
  end
end
