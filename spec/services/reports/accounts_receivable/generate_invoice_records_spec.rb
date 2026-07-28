# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::AccountsReceivable::GenerateInvoiceRecords do
  it "reads identity and totals from a unified direct-bill invoice" do
    receivable = create(:ar_invoice, amount: 200, paid_amount: 50, outstanding_amount: 150)

    records = described_class.new(invoice: receivable)

    expect(records.invoice_reference).to eq(receivable.invoice.invoice_reference)
    expect(records.original_amount).to eq(200.to_d)
    expect(records.paid_amount).to eq(50.to_d)
    expect(records.outstanding_amount).to eq(150.to_d)
  end
end
