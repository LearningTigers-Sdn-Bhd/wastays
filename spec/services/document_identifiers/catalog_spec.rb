# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentIdentifiers::Catalog do
  it "keeps settled and direct-bill invoices on distinct counters and type codes" do
    expect(described_class.fetch(:invoice)).to eq(counter: "invoice", code: "7")
    expect(described_class.fetch(:ar_invoice)).to eq(counter: "ar_invoice", code: "4")
  end
end
