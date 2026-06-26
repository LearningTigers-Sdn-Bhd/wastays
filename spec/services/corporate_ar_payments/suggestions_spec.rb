# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateArPayments::Suggestions do
  let(:later_invoice) do
    instance_double("ArInvoice", id: 1, invoice_number: 2, formatted_invoice_number: "WS-I0000002", due_on: Date.current + 10.days, outstanding_amount: BigDecimal("100"))
  end
  let(:earlier_invoice) do
    instance_double("ArInvoice", id: 2, invoice_number: 1, formatted_invoice_number: "WS-I0000001", due_on: Date.current + 1.day, outstanding_amount: BigDecimal("200"))
  end

  it "suggests amounts from oldest due first" do
    suggestions = described_class.call(invoices: [ later_invoice, earlier_invoice ], amount: 250)
    expect(suggestions.first[:ar_invoice_id]).to eq(2)
    expect(suggestions.first[:suggested_amount]).to eq("200.0")
  end

  it "stops when remaining amount is zero" do
    suggestions = described_class.call(invoices: [ earlier_invoice, later_invoice ], amount: 50)
    expect(suggestions).to be_nil
  end

  it "returns empty when no invoices" do
    expect(described_class.call(invoices: [], amount: 100)).to eq([])
  end
end
