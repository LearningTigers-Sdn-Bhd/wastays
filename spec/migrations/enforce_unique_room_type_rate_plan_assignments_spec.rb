# frozen_string_literal: true

require "rails_helper"

RSpec.describe "unique room category rate-plan assignments" do
  it "has a unique composite database index" do
    index = ActiveRecord::Base.connection.indexes(:room_type_rate_plans)
      .find { |candidate| candidate.name == "idx_room_type_rate_plans_unique_assignment" }

    expect(index).not_to be_nil
    expect(index.unique).to be(true)
    expect(index.columns).to eq(%w[room_type_id rate_plan_id])
  end
end
