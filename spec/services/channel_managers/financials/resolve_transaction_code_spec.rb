# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::Financials::ResolveTransactionCode do
  it "uses a configured service mapping before canonical and fallback resolution" do
    hotel = create(:hotel)
    source = create(:booking_source, kind: "ota")
    code = create(:transaction_code, hotel: hotel, kind: "charge", category: "other")
    create(:ota_financial_component_mapping,
      hotel: hotel, booking_source: source, transaction_code: code,
      component_kind: "service", normalized_provider_type: "",
      normalized_provider_name: "resort fee")

    result = described_class.call(
      hotel: hotel, booking_source: source, provider: "channex",
      component: { kind: "service_fee", metadata: { "name" => "Resort fee" } }
    )

    expect(result).to have_attributes(transaction_code: code, mapping_status: "mapped")
  end

  it "does not classify taxes as cleaning revenue and requires configured tax rates to match" do
    hotel = create(:hotel)
    configured = create(:hotel_tax, hotel: hotel, name: "Cleaning VAT", code: "CVAT",
      rate_type: "percentage", amount: 10, charge_type: "tax", enabled: true)

    result = described_class.call(
      hotel: hotel, booking_source: nil, provider: "channex",
      component: { kind: "tax", metadata: { "name" => configured.name, "rate" => "14" } }
    )

    expect(result.mapping_status).to eq("unmapped")
    expect(result.transaction_code.system_key).to eq("ota_unmapped_tax")
  end
end
