# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioRouting::TransientRule do
  subject(:rule) do
    described_class.new(
      booking: "B", booking_id: 1, transaction_code_id: 2,
      target_folio: "F", target_folio_id: 3, effective_from: nil, effective_until: nil
    )
  end

  it "answers everything the charge-moving services read off a rule" do
    expect(rule.booking).to eq("B")
    expect(rule.booking_id).to eq(1)
    expect(rule.transaction_code_id).to eq(2)
    expect(rule.target_folio).to eq("F")
    expect(rule.target_folio_id).to eq(3)
    expect(rule.effective_from).to be_nil
    expect(rule.effective_until).to be_nil
  end

  it "refuses a reader it does not stand in for, instead of answering nil" do
    expect { rule.hotel_id }.to raise_error(NoMethodError)
  end
end
