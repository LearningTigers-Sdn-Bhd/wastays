# frozen_string_literal: true

require "rails_helper"

RSpec.describe OtaFinancialComponentMapping, type: :model do
  let(:hotel) { create(:hotel) }
  let(:source) { create(:booking_source, kind: "ota") }
  let(:transaction_code) { create(:transaction_code, hotel: hotel, kind: "charge", category: "other") }
  let(:attributes) do
    {
      hotel: hotel,
      booking_source: source,
      transaction_code: transaction_code,
      provider: " Channex ",
      component_kind: "fee",
      normalized_provider_type: " Service Charge ",
      normalized_provider_name: "Cleaning Fee"
    }
  end

  it "normalizes and persists a provider/source component mapping" do
    mapping = described_class.create!(attributes)

    expect(mapping).to have_attributes(
      provider: "channex",
      normalized_provider_type: "service_charge",
      normalized_provider_name: "cleaning_fee",
      active: true
    )
  end

  it "allows service mappings with a blank provider type and rejects accommodation mappings" do
    service_mapping = described_class.new(attributes.merge(component_kind: "service", normalized_provider_type: ""))
    accommodation_mapping = described_class.new(attributes.merge(component_kind: "accommodation"))

    expect(service_mapping).to be_valid
    expect(accommodation_mapping).not_to be_valid
  end

  it "allows a provider-level default without a booking source" do
    expect(described_class.new(attributes.merge(booking_source: nil))).to be_valid
  end

  it "requires an OTA booking source when a source is present" do
    mapping = described_class.new(attributes.merge(booking_source: create(:booking_source, kind: "manual")))

    expect(mapping).not_to be_valid
    expect(mapping.errors[:booking_source]).to include("must be an OTA source")
  end

  it "requires the transaction code to belong to the hotel" do
    other_code = create(:transaction_code, hotel: create(:hotel))
    mapping = described_class.new(attributes.merge(transaction_code: other_code))

    expect(mapping).not_to be_valid
    expect(mapping.errors[:transaction_code]).to include("must belong to the same hotel")
  end

  it "requires a transaction-code kind compatible with the component" do
    tax_code = create(:transaction_code, hotel: hotel, kind: "tax", category: "tax")
    mapping = described_class.new(attributes.merge(component_kind: "fee", transaction_code: tax_code))

    expect(mapping).not_to be_valid
    expect(mapping.errors[:transaction_code]).to include("must be a charge code for fee components")
  end

  it "enforces distinct provider defaults and source overrides in the database" do
    described_class.create!(attributes.merge(booking_source: nil))
    provider_duplicate = described_class.new(attributes.merge(booking_source: nil))

    expect(provider_duplicate).not_to be_valid
    expect { provider_duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)

    source_override = described_class.create!(attributes)
    source_duplicate = described_class.new(attributes)

    expect(source_duplicate).not_to be_valid
    expect { source_duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "exposes only enabled mappings through the active scope" do
    active = described_class.create!(attributes)
    described_class.create!(attributes.merge(normalized_provider_name: "resort fee", active: false))

    expect(described_class.active).to contain_exactly(active)
  end
end
