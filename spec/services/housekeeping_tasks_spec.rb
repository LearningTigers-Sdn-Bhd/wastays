# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks do
  it "keeps the operational contexts explicit" do
    expect(HousekeepingRequest::OPERATIONAL_CONTEXTS).to contain_exactly(
      "vacant_room_task", "checkout_turnover"
    )
  end
end
