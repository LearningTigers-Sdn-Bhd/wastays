# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelOps::PopulateRatesAvailability do
  let(:hotel) { create(:hotel) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:room) { create(:room_type, hotel: hotel, quantity: 3, base_price: 100, max_adults: 2) }
  let(:plan) { room.standard_rate_plan }
  let(:start_date) { Date.current.beginning_of_week }
  let(:end_date) { start_date + 6.days }

  it "materializes inventory and only differing weekend rates" do
    result = described_class.call(
      hotel: hotel, actor: actor, start_date: start_date, end_date: end_date,
      weekend_days: [ 6, 0 ],
      room_rules: [ { room_type_id: room.id, quantity: 2, status: "open" } ],
      weekend_rules: [ {
        room_type_id: room.id, rate_plan_id: plan.id,
        adjustment_mode: "percent", adjustment_value: "10"
      } ]
    )

    expect(result).to be_success
    expect(room.room_inventories.where(date: start_date..end_date).count).to eq(7)
    expect(room.room_inventories.where(quantity: 2, status: "open").count).to eq(7)
    weekend_rates = room.room_rates.where(applied_rule_type: "onboarding_weekend").order(:date)
    expect(weekend_rates.count).to eq(2)
    expect(weekend_rates.map(&:price)).to all(eq(110.to_d))
  end

  it "materializes a complete adjusted per-person matrix" do
    pax_hotel = create(:hotel, :per_person)
    pax_actor = create(:user, account: pax_hotel.account)
    pax_room = create(:room_type, hotel: pax_hotel, quantity: 1, max_adults: 3)
    pax_plan = pax_room.standard_rate_plan
    assignment = pax_room.room_type_rate_plans.find_by!(rate_plan: pax_plan)
    [ 80, 120, 150 ].each_with_index { |price, index| assignment.occupancy_prices.create!(adults: index + 1, price: price) }

    result = described_class.call(
      hotel: pax_hotel, actor: pax_actor, start_date: start_date, end_date: end_date,
      weekend_days: [ 6 ],
      room_rules: [ { room_type_id: pax_room.id, quantity: 1, status: "open" } ],
      weekend_rules: [ {
        room_type_id: pax_room.id, rate_plan_id: pax_plan.id,
        adjustment_mode: "amount", adjustment_value: "10"
      } ]
    )

    expect(result).to be_success
    rate = pax_room.room_rates.find_by!(applied_rule_type: "onboarding_weekend")
    expect(rate.occupancy_prices).to eq("1" => "90.0", "2" => "130.0", "3" => "160.0")
  end

  it "requests one consolidated ARI synchronization for the populated scope" do
    room
    hotel.update!(preferred_channel_manager: "channex")

    expect {
      described_class.call(
        hotel: hotel, actor: actor, start_date: start_date, end_date: end_date,
        weekend_days: [ 6 ],
        room_rules: [ { room_type_id: room.id, quantity: 2, status: "open" } ],
        weekend_rules: [ {
          room_type_id: room.id, rate_plan_id: plan.id,
          adjustment_mode: "amount", adjustment_value: "5"
        } ]
      )
    }.to have_enqueued_job(ChannelManagers::SyncJob).exactly(:once)

    queued = ActiveJob::Base.queue_adapter.enqueued_jobs
    expect(queued.count { |job| job[:job] == ChannelManagers::BufferAriSyncJob }).to eq(0)
  end
end
