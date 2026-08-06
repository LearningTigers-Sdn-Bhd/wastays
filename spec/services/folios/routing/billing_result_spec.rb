# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::BillingResult do
  it "carries the ensured billing party and target folio" do
    result = described_class.success(party: "Company", target_folio: "Company Folio")

    expect(result).to be_success
    expect(result.party).to eq("Company")
    expect(result.target_folio).to eq("Company Folio")
  end

  it "carries an error without billing records when it fails" do
    result = described_class.failure("Unable to configure company billing")

    expect(result).not_to be_success
    expect(result.error).to eq("Unable to configure company billing")
    expect(result.party).to be_nil
    expect(result.target_folio).to be_nil
  end
end
