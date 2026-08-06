require "rails_helper"

RSpec.describe Discounts::Quote do
  let(:folio) { create(:booking_folio) }
  let(:hotel) { folio.hotel }

  def charge(amount:, category: "other", posting_date: Date.current, transaction_code: nil, **attributes)
    create(:folio_transaction, booking_folio: folio, amount:, category:, posting_date:, transaction_code:, **attributes)
  end

  it "calculates room-only percentage discounts and excludes tax and future charges" do
    charge(amount: 100, category: "accommodation")
    charge(amount: 50)
    charge(amount: 8, category: "tax")
    charge(amount: 25, category: "accommodation", posting_date: Date.tomorrow)
    discount = create(:hotel_discount, hotel:, pricing_type: "percentage", rate_value: 10,
      application_scope: "room_charges", allow_amount_override: false)

    result = described_class.call(discount:, folio:, posting_date: Date.current, preview: true)

    expect(result).to be_success
    expect(result.base_amount).to eq(100.to_d)
    expect(result.amount).to eq(10.to_d)
  end

  it "limits selected-charge discounts to configured transaction codes" do
    selected = create(:transaction_code, hotel:)
    other = create(:transaction_code, hotel:)
    charge(amount: 80, transaction_code: selected)
    charge(amount: 40, transaction_code: other)
    discount = create(:hotel_discount, hotel:, pricing_type: "fixed", rate_value: 20,
      application_scope: "selected_charges", allow_amount_override: false,
      applicable_transaction_codes: [ selected ])

    result = described_class.call(discount:, folio:, posting_date: Date.current, preview: true)

    expect(result.base_amount).to eq(80.to_d)
    expect(result.amount).to eq(20.to_d)
    expect(result.metadata[:discount_eligible_transaction_ids]).to eq([ folio.folio_transactions.order(:id).first.id ])
  end

  it "rejects an amount above the eligible subtotal" do
    charge(amount: 30)
    discount = create(:hotel_discount, hotel:)

    result = described_class.call(discount:, folio:, posting_date: Date.current, requested_amount: 31, preview: true)

    expect(result).not_to be_success
    expect(result.error).to include("cannot exceed")
  end

  it "detects a stale calculation fingerprint" do
    charge(amount: 100)
    discount = create(:hotel_discount, hotel:, pricing_type: "percentage", rate_value: 10, allow_amount_override: false)
    preview = described_class.call(discount:, folio:, posting_date: Date.current, preview: true)
    charge(amount: 25)

    result = described_class.call(discount:, folio:, posting_date: Date.current, expected_fingerprint: preview.fingerprint)

    expect(result).not_to be_success
    expect(result.error).to include("Folio charges changed")
    expect(result.amount).to eq(12.5.to_d)
  end
end
