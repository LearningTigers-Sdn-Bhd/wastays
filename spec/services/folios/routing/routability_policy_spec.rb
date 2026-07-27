# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::RoutabilityPolicy do
  it "returns active charge parents and excludes generated, payment, and archived codes" do
    hotel = create(:hotel)
    parent = create(:transaction_code, hotel:, kind: "charge", code: "MINIBAR-P", system_key: "minibar_parent")
    archived = create(:transaction_code, hotel:, kind: "charge", code: "OLD-P", system_key: "old_parent", active: false)
    payment = create(:transaction_code, hotel:, kind: "payment", category: "cash", code: "CASH-P", system_key: "policy_cash_payment")
    generated = create(:transaction_code, hotel:, kind: "charge", category: "tax", code: "TAX-P", system_key: "custom_tax_output")
    create(:hotel_tax, hotel:, transaction_code: generated)

    result = described_class.parent_codes(hotel:).to_a

    expect(result).to include(parent)
    expect(result).not_to include(archived, payment, generated)
  end
end
