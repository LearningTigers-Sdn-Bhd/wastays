# frozen_string_literal: true

require "rails_helper"

RSpec.describe OtaFinancialComponent, type: :model do
  it "persists a normalized accommodation posting fact" do
    component = create(:ota_financial_component,
      normalized_provider_name: nil,
      normalized_provider_type: nil,
      original_currency: "myr",
      currency: "myr")

    expect(component).to have_attributes(
      normalized_provider_name: "room_charge",
      normalized_provider_type: "accommodation",
      original_currency: "MYR",
      currency: "MYR",
      is_inclusive: false,
      allocation_rounding_amount: 0.to_d,
      metadata: {}
    )
  end

  it "requires an accommodation component to identify its booking room" do
    component = build(:ota_financial_component, booking_room: nil)

    expect(component).not_to be_valid
    expect(component.errors[:booking_room]).to include("is required for accommodation components")
    expect { component.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "accepts zero gross effect for inclusive tax and a positive posting" do
    component = build(:ota_financial_component,
      component_kind: "tax",
      booking_room: nil,
      is_inclusive: true,
      gross_effect_amount: 0,
      posting_amount: 12)
    component.transaction_code = build(:transaction_code, hotel: component.ota_financial_snapshot.hotel, kind: "tax", category: "tax")

    expect(component).to be_valid
  end

  it "enforces signed gross and posting effects" do
    discount = build(:ota_financial_component,
      component_kind: "discount",
      booking_room: nil,
      gross_effect_amount: 10,
      posting_amount: 10)

    expect(discount).not_to be_valid
    expect(discount.errors[:gross_effect_amount]).to be_present
    expect(discount.errors[:posting_amount]).to be_present
  end

  it "requires the booking, room, and transaction code to share the snapshot context" do
    hotel = create(:hotel)
    booking = create(:booking, hotel: hotel)
    snapshot = create(:ota_financial_snapshot, hotel: hotel, booking: booking)
    component = build(:ota_financial_component, ota_financial_snapshot: snapshot, booking: booking)
    other_booking = create(:booking, hotel: hotel)
    component.booking_room = build(:booking_room, booking: other_booking, room_type: create(:room_type, hotel: hotel))
    component.transaction_code = build(:transaction_code, hotel: create(:hotel))

    expect(component).not_to be_valid
    expect(component.errors[:booking_room]).to include("must belong to the component booking")
    expect(component.errors[:transaction_code]).to include("must belong to the snapshot hotel")
  end

  it "accepts child bookings belonging to a group snapshot" do
    snapshot = create(:ota_financial_snapshot, :for_group_booking)
    booking = create(:booking, hotel: snapshot.hotel, group_booking: snapshot.group_booking)
    component = build(:ota_financial_component, ota_financial_snapshot: snapshot, booking: booking)

    expect(component).to be_valid
  end

  it "enforces stable-key idempotency within a snapshot and booking" do
    existing = create(:ota_financial_component)
    duplicate = build(:ota_financial_component,
      ota_financial_snapshot: existing.ota_financial_snapshot,
      booking: existing.booking,
      booking_room: existing.booking_room,
      stable_key: existing.stable_key)

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "enforces allowed component and mapping values in the database" do
    component = build(:ota_financial_component, component_kind: "commission", mapping_status: "unknown")

    expect(component).not_to be_valid
    expect { component.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "cannot be updated or destroyed after creation" do
    component = create(:ota_financial_component)

    expect(component.update(provider_name: "Changed")).to be(false)
    expect(component.reload.provider_name).to eq("Room charge")
    expect(component.destroy).to be(false)
    expect(component).to be_persisted
  end
end
