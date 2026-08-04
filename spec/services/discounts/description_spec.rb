require "rails_helper"

RSpec.describe Discounts::Description do
  let(:folio) { create(:booking_folio) }
  let(:hotel) { folio.hotel }

  def quote_for(discount)
    create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")
    Discounts::Quote.call(discount:, folio:, posting_date: Date.current, preview: true)
  end

  it "names a manual discount and appends the submitted detail" do
    discount = create(:hotel_discount, hotel:, pricing_type: "manual")

    described = described_class.call(
      discount:, currency: "MYR", quote: quote_for(discount), submitted_description: "Service recovery"
    )

    expect(described).to eq("#{discount.name} · Service recovery")
  end

  it "returns just the name for a manual discount with no detail" do
    discount = create(:hotel_discount, hotel:, pricing_type: "manual")

    expect(described_class.call(discount:, currency: "MYR", quote: quote_for(discount))).to eq(discount.name)
    expect(described_class.call(discount:, currency: "MYR", quote: quote_for(discount), submitted_description: "  ")).to eq(discount.name)
  end

  it "spells out the rate and base amount for a percentage discount" do
    discount = create(:hotel_discount, hotel:, pricing_type: "percentage", rate_value: 10,
      application_scope: "room_charges", allow_amount_override: false)

    described = described_class.call(
      discount:, currency: "MYR", quote: quote_for(discount), submitted_description: "Loyalty"
    )

    expect(described).to eq("#{discount.name} · 10.00% of room charges (MYR 100.00) · Loyalty")
  end

  it "names the application scope for a fixed discount" do
    discount = create(:hotel_discount, hotel:, pricing_type: "fixed", rate_value: 20,
      application_scope: "all_eligible_charges", allow_amount_override: false)

    described = described_class.call(discount:, currency: "MYR", quote: quote_for(discount))

    expect(described).to eq("#{discount.name} · All eligible charges")
  end
end
