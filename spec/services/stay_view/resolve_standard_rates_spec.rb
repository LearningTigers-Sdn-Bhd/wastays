# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::ResolveStandardRates do
  let(:date) { Date.new(2026, 7, 16) }

  it "prefers the master-plan dated rate over a legacy planless rate" do
    resolved = resolve([
      rate(rate_plan_id: nil, price: 120),
      rate(rate_plan_id: 7, price: 145)
    ])

    expect(resolved).to have_attributes(amount: 145.to_d, currency: "MYR", source: :room_rate)
  end

  it "falls back from the master plan to a planless dated rate and then base price" do
    expect(resolve([ rate(rate_plan_id: nil, price: 120) ])).to have_attributes(
      amount: 120.to_d, source: :room_rate
    )
    expect(resolve([])).to have_attributes(amount: 100.to_d, source: :base_price_fallback)
  end

  it "uses only the master plan currency and returns no value when pricing is genuinely missing" do
    expect(resolve([ rate(rate_plan_id: 7, price: 155, currency: "USD") ])).to have_attributes(
      amount: 100.to_d, currency: "MYR", source: :base_price_fallback
    )
    expect(resolve([], base_price: nil)).to be_nil
  end

  it "returns an immutable keyed projection" do
    result = described_class.call(room_types: [ room_type ], standard_rates: [], dates: [ date ])

    expect(result).to be_frozen
    expect(result.values.sole).to be_frozen
  end

  it "uses only an explicitly selected plan without Standard fallbacks" do
    selected = StayView::RatePlanOption.new(
      id: 9,
      name: "Flexible",
      currency: "USD",
      room_type_ids: [ 3 ],
      room_type_names: [ "Deluxe" ],
      label: "Flexible — Deluxe"
    )
    selected_rate = rate(rate_plan_id: 9, price: 175, currency: "USD")

    resolved = described_class.call(
      room_types: [ room_type(base_price: 100) ],
      standard_rates: [ rate(rate_plan_id: nil, price: 120), selected_rate ],
      dates: [ date, date + 1.day ],
      selected_rate_plan: selected
    )

    expect(resolved.fetch([ 3, date ])).to have_attributes(amount: 175.to_d, currency: "USD")
    expect(resolved.fetch([ 3, date + 1.day ])).to be_nil
  end

  it "matches the booking financial snapshot for master-plan and base-price standard rates" do
    hotel = create(:hotel, default_currency: "MYR")
    persisted_room_type = create(:room_type, hotel:, base_price: 100)
    master_plan = persisted_room_type.rate_plans.order(:id).first
    create(:room_rate, room_type: persisted_room_type, rate_plan: master_plan, date:, price: 135, currency: "MYR")

    snapshot = Bookings::BuildFinancialSnapshot.new(
      hotel:, room_type: persisted_room_type, check_in: date, check_out: date + 1.day, guest_country: "MY"
    ).call.nightly_rate_snapshot.fetch(date.iso8601)
    scalar_room_type = room_type(
      id: persisted_room_type.id,
      base_price: persisted_room_type.base_price,
      master_rate_plan_id: master_plan.id,
      rate_currency: master_plan.currency
    )
    scalar_rate = rate(
      room_type_id: persisted_room_type.id,
      rate_plan_id: master_plan.id,
      price: 135,
      currency: master_plan.currency
    )

    resolved = described_class.call(room_types: [ scalar_room_type ], standard_rates: [ scalar_rate ], dates: [ date ])

    expect(resolved.fetch([ persisted_room_type.id, date ]).amount).to eq(snapshot.fetch("price").to_d)
  end

  private

  def resolve(rates, base_price: 100)
    described_class.call(
      room_types: [ room_type(base_price:) ], standard_rates: rates, dates: [ date ]
    )[[ 3, date ]]
  end

  def room_type(id: 3, base_price: 100, master_rate_plan_id: 7, rate_currency: "MYR")
    StayView::RoomTypeRecord.new(
      id:, name: "Deluxe", room_numbers: [ "101" ], smoking_allowed: false, pets_allowed: false,
      base_price:, master_rate_plan_id:, rate_currency:
    )
  end

  def rate(room_type_id: 3, rate_plan_id:, price:, currency: "MYR")
    StayView::StandardRateRecord.new(room_type_id:, rate_plan_id:, date:, price:, currency:)
  end
end
