# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaxRuleOptionsQuery do
  let(:hotel) { create(:hotel, sst_enabled: true, tourism_tax_enabled: false, tourism_tax_amount: 10) }

  it "offers the statutory taxes alongside the property's own" do
    tax = hotel.hotel_taxes.create!(name: "Heritage levy", charge_type: "tax", rate_type: "percentage", amount: 2, enabled: true)

    keys = described_class.new(hotel).call.map { |rule| rule[:key] }

    expect(keys).to eq([ "primary:sst_tax", "primary:tourism_tax", "hotel_tax:#{tax.id}" ])
  end

  # An inactive tax is still assignable — it is stored and skipped at posting
  # time — so it stays in the list and says so.
  it "labels an inactive tax rather than dropping it" do
    choices = described_class.new(hotel).choices

    expect(choices).to include(
      { label: "Service Tax (SST)", value: "primary:sst_tax" },
      { label: "Tourism Tax · Inactive", value: "primary:tourism_tax" }
    )
  end
end
