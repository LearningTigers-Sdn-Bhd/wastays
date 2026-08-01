# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::RestoreLateCheckoutRoomStatuses do
  it "exposes the booking-scoped restoration service" do
    expect(described_class).to respond_to(:new)
  end
end
