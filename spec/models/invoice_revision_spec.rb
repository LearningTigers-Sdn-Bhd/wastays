# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceRevision do
  it "preserves an issued revision as immutable history" do
    revision = create(:invoice).current_revision

    expect(revision.update(snapshot: { changed: true })).to be(false)
    expect(revision.errors[:base]).to include("Invoice revisions are immutable.")
    expect(revision.destroy).to be(false)
    expect(revision).to be_persisted
  end

  it "does not allow the current revision pointer to reference a missing revision" do
    invoice = create(:invoice)

    expect(invoice.update(current_revision_number: 2)).to be(false)
    expect(invoice.errors[:current_revision_number]).to include("must reference an issued revision")
  end
end
