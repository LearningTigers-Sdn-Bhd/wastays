# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260810090000_materialize_system_rate_plans")

RSpec.describe MaterializeSystemRatePlans do
  subject(:migration) { described_class.new }

  around do |example|
    unless ActiveRecord::Base.connection.column_exists?(:room_rates, :walk_in_price)
      ActiveRecord::Migration.suppress_messages { migration.down }
      RoomRate.reset_column_information
    end

    example.run
  ensure
    if ActiveRecord::Base.connection.column_exists?(:room_rates, :walk_in_price)
      ActiveRecord::Migration.suppress_messages { migration.up }
      RoomRate.reset_column_information
    end
  end

  it "materializes virtual prices and historical tier selections without changing captured amounts" do
    room_type = create(:room_type)
    standard = room_type.standard_rate_plan
    walk_in = room_type.walk_in_rate_plan
    corporate = room_type.corporate_rate_plan
    date = Date.current
    create(
      :room_rate,
      room_type: room_type,
      rate_plan: standard,
      date: date,
      price: 200,
      corporate_price: 175,
      min_stay: 2
    )
    create(
      :room_rate,
      room_type: room_type,
      rate_plan: nil,
      date: date,
      price: 200,
      walk_in_price: 230,
      min_stay: 3
    )
    booking_room = create(
      :booking_room,
      room_type: room_type,
      nightly_rate_snapshot: {
        date.iso8601 => { "price" => "230.0", "rate_tier" => "walk_in", "tax" => "13.80" }
      }
    )
    quote_item = create(
      :booking_quote_item,
      room_type: room_type,
      nightly_rate_snapshot: {
        date.iso8601 => { "price" => "175.0", "rate_tier" => "corporate", "fees" => "7.50" }
      }
    )

    ActiveRecord::Migration.suppress_messages { migration.up }
    RoomRate.reset_column_information

    expect(RoomRate.find_by!(room_type: room_type, rate_plan: walk_in, date: date)).to have_attributes(price: 230.to_d, min_stay: 3)
    expect(RoomRate.find_by!(room_type: room_type, rate_plan: corporate, date: date)).to have_attributes(price: 175.to_d, min_stay: 2)
    expect(booking_room.reload).to have_attributes(rate_plan_id: walk_in.id)
    expect(booking_room.nightly_rate_snapshot.fetch(date.iso8601)).to eq(
      "price" => "230.0", "tax" => "13.80", "rate_plan_id" => walk_in.id
    )
    expect(quote_item.reload.nightly_rate_snapshot.fetch(date.iso8601)).to eq(
      "price" => "175.0", "fees" => "7.50", "rate_plan_id" => corporate.id
    )
    expect(ActiveRecord::Base.connection).not_to be_column_exists(:room_rates, :walk_in_price)
    expect(ActiveRecord::Base.connection).not_to be_column_exists(:room_rates, :corporate_price)
  end

  # Nothing falls back to an unattributed row any more, so one left behind is a
  # price that silently disappears.
  describe "rows predating rate_plan_id" do
    it "adopts an unclaimed row onto the standard plan" do
      room_type = create(:room_type)
      standard = room_type.standard_rate_plan
      date = Date.current + 30
      unattributed = create(:room_rate, room_type: room_type, rate_plan: nil, date: date, price: 310, min_stay: 2)

      ActiveRecord::Migration.suppress_messages { migration.up }
      RoomRate.reset_column_information

      expect(unattributed.reload).to have_attributes(rate_plan_id: standard.id, price: 310.to_d, min_stay: 2)
    end

    it "drops one the standard plan already has a row for, which outranked it" do
      room_type = create(:room_type)
      standard = room_type.standard_rate_plan
      date = Date.current + 31
      create(:room_rate, room_type: room_type, rate_plan: standard, date: date, price: 400)
      unattributed = create(:room_rate, room_type: room_type, rate_plan: nil, date: date, price: 310)

      ActiveRecord::Migration.suppress_messages { migration.up }
      RoomRate.reset_column_information

      expect(RoomRate.where(id: unattributed.id)).to be_empty
      expect(RoomRate.find_by!(room_type: room_type, rate_plan: standard, date: date).price).to eq(400.to_d)
    end
  end

  # Nothing reads a detached plan, so retiring one has to hand its prices over
  # first — otherwise the categories it served lose them outright.
  describe "a system plan shared across categories" do
    it "moves each category's prices onto its own plan, then detaches and archives it" do
      hotel = create(:hotel)
      room_a = create(:room_type, hotel: hotel)
      room_b = create(:room_type, hotel: hotel)
      shared = create(:rate_plan, hotel: hotel, name: "House Rate")
      date = Date.current + 40

      # The legacy shape: one standard plan serving both categories.
      [ room_a, room_b ].each do |room|
        room.room_type_rate_plans.where(rate_plan: room.standard_rate_plan).destroy_all
        create(:room_type_rate_plan, room_type: room, rate_plan: shared)
      end
      create(:room_rate, room_type: room_a, rate_plan: shared, date: date, price: 210, min_stay: 2)
      create(:room_rate, room_type: room_b, rate_plan: shared, date: date, price: 340)
      shared_assignment = RoomTypeRatePlan.find_by!(room_type: room_a, rate_plan: shared)
      occupancy_price = RoomTypeRatePlanOccupancyPrice.create!(
        room_type_rate_plan: shared_assignment, adults: 1, price: 210
      )

      ActiveRecord::Migration.suppress_messages { migration.up }
      RoomRate.reset_column_information

      expect(shared.reload.archived_at).to be_present
      expect(RoomTypeRatePlan.where(rate_plan: shared)).to be_empty
      expect(RoomTypeRatePlanOccupancyPrice.where(id: occupancy_price.id)).to be_empty

      a_standard = room_a.reload.rate_plans.detect(&:standard_rate?)
      b_standard = room_b.reload.rate_plans.detect(&:standard_rate?)
      expect([ a_standard, b_standard ]).to all(be_present)
      expect(a_standard).not_to eq(shared)
      expect(a_standard).not_to eq(b_standard)

      expect(RoomRate.find_by!(room_type: room_a, rate_plan: a_standard, date: date))
        .to have_attributes(price: 210.to_d, min_stay: 2)
      expect(RoomRate.find_by!(room_type: room_b, rate_plan: b_standard, date: date).price).to eq(340.to_d)
      expect(RoomRate.where(rate_plan: shared)).to be_empty
    end

    it "keeps the dedicated plan's own row when both price the same night" do
      hotel = create(:hotel)
      room_type = create(:room_type, hotel: hotel)
      dedicated = room_type.standard_rate_plan
      shared_room = create(:room_type, hotel: hotel)
      shared = create(:rate_plan, hotel: hotel, name: "House Rate")
      create(:room_type_rate_plan, room_type: room_type, rate_plan: shared)
      create(:room_type_rate_plan, room_type: shared_room, rate_plan: shared)
      date = Date.current + 41
      create(:room_rate, room_type: room_type, rate_plan: dedicated, date: date, price: 500)
      create(:room_rate, room_type: room_type, rate_plan: shared, date: date, price: 210)

      ActiveRecord::Migration.suppress_messages { migration.up }
      RoomRate.reset_column_information

      expect(RoomRate.where(room_type: room_type, date: date, rate_plan: dedicated).pluck(:price)).to eq([ 500.to_d ])
      expect(RoomRate.where(rate_plan: shared)).to be_empty
    end
  end

  # UpdateStayService stamped rate_tier "standard" onto every entry it touched,
  # whatever plan the booking was on — so it never meant "the Standard plan".
  it "leaves a booking sold on a custom plan pointing at that plan" do
    room_type = create(:room_type)
    custom = create(:rate_plan, :custom, hotel: room_type.hotel)
    create(:room_type_rate_plan, room_type: room_type, rate_plan: custom)
    date = Date.current + 32
    booking_room = create(
      :booking_room,
      room_type: room_type,
      rate_plan: custom,
      nightly_rate_snapshot: {
        date.iso8601 => { "price" => "150.0", "rate_tier" => "standard", "tax" => "9.00" }
      }
    )

    ActiveRecord::Migration.suppress_messages { migration.up }
    RoomRate.reset_column_information

    expect(booking_room.reload.rate_plan_id).to eq(custom.id)
    expect(booking_room.nightly_rate_snapshot.fetch(date.iso8601)).to eq(
      "price" => "150.0", "tax" => "9.00", "rate_plan_id" => custom.id
    )
  end
end
