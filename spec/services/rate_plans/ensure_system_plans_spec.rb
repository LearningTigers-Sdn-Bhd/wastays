# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePlans::EnsureSystemPlans do
  it "idempotently restores a missing dedicated system plan" do
    room_type = create(:room_type)
    removed_plan = room_type.walk_in_rate_plan
    retained_plan_ids = [ room_type.standard_rate_plan.id, room_type.corporate_rate_plan.id ]
    removed_plan.destroy!

    expect {
      described_class.call!(room_type: room_type)
    }.to change { room_type.rate_plans.reload.where(kind: "walk_in").count }.from(0).to(1)

    expect(room_type.rate_plans.where(kind: %w[standard corporate]).pluck(:id)).to match_array(retained_plan_ids)
    expect(room_type.walk_in_rate_plan.id).not_to eq(removed_plan.id)
  end
end
