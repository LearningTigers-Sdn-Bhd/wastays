# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::MarkUnderCorrection do
  it "marks the unified and compatibility documents under correction" do
    folio = create(:booking_folio, status: "closed")
    invoice = Invoices::Finalize.call!(folio:, issued_by: nil, balance: 0)

    expect(described_class.call!(folio:)).to eq(invoice)
    expect(invoice.reload).to be_under_correction
    expect(folio.invoice.reload).to be_under_correction
  end
end
