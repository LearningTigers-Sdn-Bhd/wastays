# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePlans::Attach do
  let(:hotel) { create(:hotel) }
  let(:first_room) { create(:room_type, hotel: hotel, name: "Deluxe", base_price: 200) }
  let(:second_room) { create(:room_type, hotel: hotel, name: "Villa", base_price: 500) }

  it "finds a plan and atomically attaches multiple rooms with independent defaults" do
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Flexible")

    result = described_class.call(
      hotel: hotel,
      rate_plan_id: plan.id,
      rate_plan_name: plan.name,
      room_type_ids: [ first_room.id, second_room.id ]
    )

    expect(result).to be_success
    expect(result.rate_plan).to eq(plan)
    expect(result.attached_rooms).to match_array([ first_room, second_room ])
    expect(result.attached_count).to eq(2)
    expect(plan.room_type_rate_plans.where(room_type: [ first_room, second_room ]).pluck(:pricing_mode, :pricing_value))
      .to contain_exactly([ "multiplier", 0.to_d ], [ "multiplier", 0.to_d ])
  end

  it "treats existing assignments as successful no-ops" do
    plan = create(:rate_plan, :custom, hotel: hotel)
    existing = create(:room_type_rate_plan, rate_plan: plan, room_type: first_room, pricing_mode: "offset", pricing_value: 25)

    result = described_class.call(
      hotel: hotel,
      rate_plan_id: plan.id,
      rate_plan_name: plan.name,
      room_type_ids: [ first_room.id ]
    )

    expect(result).to be_success
    expect(result.attached_count).to eq(0)
    expect(existing.reload).to have_attributes(pricing_mode: "offset", pricing_value: 25.to_d)
  end

  it "initializes each per-person room to its own capacity" do
    pax_hotel = create(:hotel, :per_person)
    small_room = create(:room_type, hotel: pax_hotel, max_adults: 2, base_price: 80)
    large_room = create(:room_type, hotel: pax_hotel, max_adults: 12, base_price: 100)

    result = described_class.call(
      hotel: pax_hotel,
      rate_plan_name: "Guest Offer",
      room_type_ids: [ small_room.id, large_room.id ]
    )

    expect(result).to be_success
    assignments = result.rate_plan.room_type_rate_plans.index_by(&:room_type_id)
    expect(assignments.fetch(small_room.id).occupancy_prices.count).to eq(2)
    expect(assignments.fetch(large_room.id).occupancy_prices.count).to eq(12)
    expect(assignments.fetch(small_room.id).occupancy_prices.order(:adults).last.price).to eq(160.to_d)
    expect(assignments.fetch(large_room.id).occupancy_prices.order(:adults).last.price).to eq(1_200.to_d)
  end

  it "rejects cross-hotel rooms before creating a typed plan" do
    foreign_room = create(:room_type)

    result = described_class.call(
      hotel: hotel,
      rate_plan_name: "Must Roll Back",
      room_type_ids: [ first_room.id, foreign_room.id ]
    )

    expect(result).not_to be_success
    expect(hotel.rate_plans.where(name: "Must Roll Back")).to be_empty
  end

  it "rolls back a newly created plan and all assignments when initialization fails" do
    allow(RatePlans::BootstrapAssignment).to receive(:call!).and_call_original
    allow(RatePlans::BootstrapAssignment).to receive(:call!).with(
      rate_plan: instance_of(RatePlan), room_type: second_room
    ).and_raise(ActiveRecord::RecordInvalid.new(second_room))

    result = described_class.call(
      hotel: hotel,
      rate_plan_name: "Atomic Promo",
      room_type_ids: [ first_room.id, second_room.id ]
    )

    expect(result).not_to be_success
    expect(hotel.rate_plans.where(name: "Atomic Promo")).to be_empty
    expect(first_room.rate_plans.where(name: "Atomic Promo")).to be_empty
  end

  it "rejects an empty room selection" do
    Thread.current[:skip_ari_sync] = :outer_operation
    result = described_class.call(hotel: hotel, rate_plan_name: "Promo", room_type_ids: [])

    expect(result).not_to be_success
    expect(result.error).to include("Select at least one room category")
    expect(Thread.current[:skip_ari_sync]).to eq(:outer_operation)
  ensure
    Thread.current[:skip_ari_sync] = nil
  end

  it "schedules one batched channel sync for newly attached rooms" do
    plan = create(:rate_plan, :custom, hotel: hotel)
    allow(ActiveRecord).to receive(:after_all_transactions_commit).and_yield
    allow(ChannelManagers::SyncRatePlanAri).to receive(:call)

    described_class.call(
      hotel: hotel,
      rate_plan_id: plan.id,
      rate_plan_name: plan.name,
      room_type_ids: [ first_room.id, second_room.id ]
    )

    expect(ChannelManagers::SyncRatePlanAri).to have_received(:call).once.with(
      rate_plan: plan,
      room_type_ids: match_array([ first_room.id, second_room.id ])
    )
  end
end
