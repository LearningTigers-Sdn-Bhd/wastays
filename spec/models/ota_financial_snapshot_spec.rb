# frozen_string_literal: true

require "rails_helper"

RSpec.describe OtaFinancialSnapshot, type: :model do
  it "persists a normalized single-booking financial snapshot" do
    snapshot = create(:ota_financial_snapshot, provider: " Channex ", original_currency: "myr", currency: "myr")

    expect(snapshot).to have_attributes(
      provider: "channex",
      original_currency: "MYR",
      currency: "MYR",
      current: true,
      policy_snapshot: {},
      metadata: {}
    )
  end

  it "supports a group booking as the exclusive target" do
    snapshot = build(:ota_financial_snapshot, :for_group_booking)

    expect(snapshot).to be_valid
    expect(snapshot.booking).to be_nil
    expect(snapshot.group_booking).to be_present
  end

  it "requires exactly one booking or group booking target" do
    snapshot = build(:ota_financial_snapshot, booking: nil, group_booking: nil)
    expect(snapshot).not_to be_valid

    snapshot.booking = build(:booking, hotel: snapshot.hotel)
    snapshot.group_booking = build(:group_booking, hotel: snapshot.hotel)
    expect(snapshot).not_to be_valid
    expect(snapshot.errors[:base]).to include("must belong to exactly one booking or group booking")
  end

  it "requires the target to belong to the snapshot hotel" do
    snapshot = build(:ota_financial_snapshot, booking: build(:booking, hotel: create(:hotel)))

    expect(snapshot).not_to be_valid
    expect(snapshot.errors[:base]).to include("financial snapshot target must belong to the snapshot hotel")
  end

  it "validates currencies, statuses, reasons, and nonnegative totals" do
    snapshot = build(:ota_financial_snapshot,
      currency: "not-money",
      reconciliation_status: "ignored",
      variance_reason: "guess",
      gross_amount: -1)

    expect(snapshot).not_to be_valid
    expect(snapshot.errors[:currency]).to be_present
    expect(snapshot.errors[:reconciliation_status]).to be_present
    expect(snapshot.errors[:variance_reason]).to be_present
    expect(snapshot.errors[:gross_amount]).to be_present
  end

  it "enforces one current snapshot per booking in the database" do
    existing = create(:ota_financial_snapshot)
    duplicate = build(:ota_financial_snapshot,
      hotel: existing.hotel,
      booking: existing.booking,
      channel_manager_reference: "another-reference",
      provider_revision_id: "another-revision")

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows historical snapshots while enforcing provider revision idempotency" do
    existing = create(:ota_financial_snapshot, current: false, superseded_at: Time.current)
    historical = build(:ota_financial_snapshot,
      hotel: existing.hotel,
      booking: existing.booking,
      current: false,
      channel_manager_reference: "another-reference")
    expect(historical.save!).to be(true)

    duplicate_revision = build(:ota_financial_snapshot,
      hotel: existing.hotel,
      booking: existing.booking,
      current: false,
      channel_manager_reference: existing.channel_manager_reference,
      provider_revision_id: existing.provider_revision_id)
    expect(duplicate_revision).not_to be_valid
    expect { duplicate_revision.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "prevents financial mutation while allowing lifecycle supersession" do
    snapshot = create(:ota_financial_snapshot)

    expect(snapshot.update(gross_amount: snapshot.gross_amount + 1)).to be(false)
    expect(snapshot.errors[:base]).to include("OTA financial snapshots are immutable")
    snapshot.reload
    expect(snapshot.update(current: false, superseded_at: Time.current)).to be(true)
  end

  it "restricts deletion while components exist" do
    snapshot = create(:ota_financial_snapshot)
    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking: snapshot.booking)

    expect(snapshot.destroy).to be(false)
    expect(snapshot.errors[:base]).to be_present
  end
end
