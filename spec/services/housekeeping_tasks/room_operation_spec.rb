# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::RoomOperation do
  it "is the shared base for each room mutation service" do
    expect(HousekeepingTasks::AssignRoom.superclass).to eq(described_class)
    expect(HousekeepingTasks::UpdateRoomRemarks.superclass).to eq(described_class)
    expect(HousekeepingTasks::UpdateRoomStatus.superclass).to eq(described_class)
  end
end
