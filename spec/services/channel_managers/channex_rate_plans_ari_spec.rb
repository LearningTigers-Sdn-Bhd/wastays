# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Channex rate plan and ARI contracts" do
  let(:hotel) { create(:hotel, :per_person, name: "Occupancy Hotel") }
  let(:room_type) { create(:room_type, hotel: hotel, max_adults: 3, max_children: 2) }
  let(:rate_plan) { create(:rate_plan, :custom, hotel: hotel, room_type: room_type, base_occupancy: 2) }
  let(:assignment) { rate_plan.room_type_rate_plans.find_by!(room_type: room_type) }
  let(:adapter) { ChannelManagers::ChannexAdapter.new(hotel: hotel) }
  let(:client) { instance_double(Channex::Client) }

  before do
    allow(Channex::Client).to receive(:new).and_return(client)
    hotel.create_channel_mapping!(provider: "channex", external_id: "property-1")
    room_type.create_channel_mapping!(provider: "channex", external_id: "room-1")
  end

  def create_ladder(prices = [ 100.11, 150.22, 200.33 ])
    prices.each_with_index do |price, index|
      assignment.occupancy_prices.create!(adults: index + 1, price: price)
    end
  end

  def map_assignment(external_id = "plan-1")
    assignment.create_channel_mapping!(provider: "channex", external_id: external_id)
  end

  describe "rate plan structure" do
    it "sends every occupancy, the clamped primary occupancy, decimals, and flattened child fees" do
      create_ladder
      create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 0, max_age: 17)
      rate_plan.update!(channex_children_fee: 25.5, channex_infant_fee: 0)

      expect(client).to receive(:post).with("/rate_plans", {
        rate_plan: hash_including(
          room_type_id: "room-1",
          sell_mode: "per_person",
          rate_mode: "manual",
          children_fee: "25.50",
          infant_fee: "0.00",
          options: [
            { occupancy: 1, is_primary: false, rate: "100.11" },
            { occupancy: 2, is_primary: true, rate: "150.22" },
            { occupancy: 3, is_primary: false, rate: "200.33" }
          ]
        )
      }).and_return({ "data" => { "id" => "plan-1" } })

      expect(adapter.sync_rate_plan(rate_plan, room_type: room_type)).to eq("plan-1")
    end

    it "builds the option ladder for an assignment that derives from the standard plan" do
      assignment.occupancy_prices.destroy_all
      assignment.update!(pricing_mode: "multiplier", pricing_value: 10)
      standard_assignment = room_type.standard_rate_plan.room_type_rate_plans.find_by!(room_type: room_type)
      [ 100, 150, 200 ].each_with_index do |price, index|
        standard_assignment.occupancy_prices.create!(adults: index + 1, price: price)
      end

      expect(client).to receive(:post).with("/rate_plans", {
        rate_plan: hash_including(
          options: [
            { occupancy: 1, is_primary: false, rate: "110.00" },
            { occupancy: 2, is_primary: true, rate: "165.00" },
            { occupancy: 3, is_primary: false, rate: "220.00" }
          ]
        )
      }).and_return({ "data" => { "id" => "plan-1" } })

      expect(adapter.sync_rate_plan(rate_plan, room_type: room_type)).to eq("plan-1")
    end

    it "creates one maximum-occupancy option for per-room plans" do
      per_room_hotel = create(:hotel)
      per_room = create(:room_type, hotel: per_room_hotel, max_adults: 4)
      plan = create(:rate_plan, hotel: per_room_hotel, room_type: per_room, base_occupancy: 2)
      per_room_hotel.create_channel_mapping!(provider: "channex", external_id: "property-2")
      per_room.create_channel_mapping!(provider: "channex", external_id: "room-2")
      per_room_adapter = ChannelManagers::ChannexAdapter.new(hotel: per_room_hotel)

      expect(client).to receive(:post).with("/rate_plans", {
        rate_plan: hash_including(
          sell_mode: "per_room",
          rate_mode: "manual",
          options: [ { occupancy: 4, is_primary: true, rate: 0 } ]
        )
      }).and_return({ "data" => { "id" => "plan-2" } })

      per_room_adapter.sync_rate_plan(plan, room_type: per_room)
    end
  end

  describe "occupancy ARI" do
    before do
      create_ladder
      map_assignment
      allow(client).to receive(:get).with("/channels").and_return({ "data" => [] })
    end

    it "sends the complete resolver-backed occupancy collection and max_stay" do
      date = Date.current
      rate_plan.room_rates.create!(
        room_type: room_type,
        date: date,
        currency: "MYR",
        price: 200.33,
        occupancy_prices: { "1" => "101.12", "2" => "151.23", "3" => "201.34" },
        max_stay: 7
      )

      expect(client).to receive(:post).with("/restrictions", {
        values: [ hash_including(
          rate_plan_id: "plan-1",
          date_from: date.to_s,
          date_to: date.to_s,
          rate: [ [ 1, "101.12" ], [ 2, "151.23" ], [ 3, "201.34" ] ],
          max_stay: 7
        ) ]
      }).and_return({ "data" => [ { "id" => "restriction-task" } ] })

      result = adapter.push_ari(
        date_range: date..date,
        sync_availability: false,
        rate_plan_ids: [ rate_plan.id ]
      )

      expect(result).to have_attributes(status: :full_success, task_ids: { restrictions: "restriction-task" })
    end

    it "compresses dates only when every occupancy price and restriction matches" do
      first = Date.current
      second = first + 1.day
      rate_plan.room_rates.create!(room_type: room_type, date: first, currency: "MYR", price: 200, occupancy_prices: { "1" => 100, "2" => 150, "3" => 200 })
      rate_plan.room_rates.create!(room_type: room_type, date: second, currency: "MYR", price: 201, occupancy_prices: { "1" => 100, "2" => 150, "3" => 201 })

      expect(client).to receive(:post).with("/restrictions", hash_including(
        values: [
          hash_including(date_from: first.to_s, date_to: first.to_s, rate: [ [ 1, "100.00" ], [ 2, "150.00" ], [ 3, "200.00" ] ]),
          hash_including(date_from: second.to_s, date_to: second.to_s, rate: [ [ 1, "100.00" ], [ 2, "150.00" ], [ 3, "201.00" ] ])
        ]
      )).and_return({ "data" => { "id" => "task-2" } })

      adapter.push_ari(
        date_range: first..second,
        sync_availability: false,
        rate_plan_ids: [ rate_plan.id ]
      )
    end

    it "resolves a derived occupancy ladder from standard daily overrides" do
      date = Date.current
      assignment.occupancy_prices.destroy_all
      assignment.update!(pricing_mode: "multiplier", pricing_value: 10)
      standard = room_type.standard_rate_plan
      standard_assignment = standard.room_type_rate_plans.find_by!(room_type: room_type)
      [ 100, 150, 200 ].each_with_index do |price, index|
        standard_assignment.occupancy_prices.create!(adults: index + 1, price: price)
      end
      standard.room_rates.create!(
        room_type: room_type,
        date: date,
        currency: "MYR",
        price: 210,
        occupancy_prices: { "1" => 110, "2" => 160, "3" => 210 }
      )

      expect(client).to receive(:post).with("/restrictions", hash_including(
        values: [ hash_including(rate: [ [ 1, "121.00" ], [ 2, "176.00" ], [ 3, "231.00" ] ]) ]
      )).and_return({ "data" => { "id" => "derived-task" } })

      result = adapter.push_ari(
        date_range: date..date,
        sync_availability: false,
        rate_plan_ids: [ rate_plan.id ]
      )

      expect(result.status).to eq(:full_success)
    end

    it "treats Channex warnings as terminal rejected data" do
      date = Date.current
      expect(client).to receive(:post).with("/restrictions", anything).and_return(
        "data" => [ { "id" => "rejected-task" } ],
        "meta" => { "warnings" => [ { "message" => "invalid occupancy" } ] }
      )

      result = adapter.push_ari(
        date_range: date..date,
        sync_availability: false,
        rate_plan_ids: [ rate_plan.id ]
      )

      expect(result).to have_attributes(status: :failure, warnings: [ { "message" => "invalid occupancy" } ])
      expect(result.task_ids).to eq({})
    end
  end

  describe "per-room ARI" do
    it "sends a resolver-backed scalar decimal string at the clamped base occupancy" do
      per_room_hotel = create(:hotel)
      per_room = create(:room_type, hotel: per_room_hotel, max_adults: 2, base_price: 199.95)
      plan = create(:rate_plan, :custom, hotel: per_room_hotel, room_type: per_room, base_occupancy: 9)
      per_room_hotel.create_channel_mapping!(provider: "channex", external_id: "property-room")
      per_room.create_channel_mapping!(provider: "channex", external_id: "room-room")
      per_room.room_type_rate_plans.find_by!(rate_plan: plan)
        .create_channel_mapping!(provider: "channex", external_id: "plan-room")
      per_room_adapter = ChannelManagers::ChannexAdapter.new(hotel: per_room_hotel)
      date = Date.current
      allow(client).to receive(:get).with("/channels").and_return({ "data" => [] })

      expect(client).to receive(:post).with("/restrictions", hash_including(
        values: [ hash_including(rate_plan_id: "plan-room", rate: "199.95") ]
      )).and_return({ "data" => { "id" => "scalar-task" } })

      result = per_room_adapter.push_ari(
        date_range: date..date,
        sync_availability: false,
        rate_plan_ids: [ plan.id ]
      )

      expect(result.status).to eq(:full_success)
    end
  end

  describe "unsupported mapped plan retirement" do
    it "stop-sells the 500-day window and retains the mapping for manual removal" do
      create_ladder([ 100, 150 ])
      mapping = map_assignment("stale-plan")
      range = Date.current..(Date.current + 499.days)

      expect(client).to receive(:post).with("/restrictions", {
        values: [ {
          property_id: "property-1",
          rate_plan_id: "stale-plan",
          date_from: range.first.to_s,
          date_to: range.last.to_s,
          stop_sell: 1
        } ]
      }).and_return({ "data" => { "id" => "retirement-task" } })

      result = adapter.push_ari(
        date_range: range,
        sync_availability: false,
        rate_plan_ids: [ rate_plan.id ]
      )

      expect(result.status).to eq(:partial_success)
      expect(result.warnings.first[:reason]).to match(/manual removal remains outstanding/i)
      expect(mapping.reload.external_id).to eq("stale-plan")
      expect(assignment.reload.channel_mapping).to eq(mapping)
    end
  end
end
