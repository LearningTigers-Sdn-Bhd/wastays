# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260728111000_enforce_unified_invoice_integrity")

RSpec.describe EnforceUnifiedInvoiceIntegrity do
  before(:context) { described_class.new.up }
  after(:context) { described_class.new.down }

  it "rejects direct SQL updates to unified invoice revisions" do
    revision = create(:invoice).current_revision

    expect { revision.update_columns(snapshot: { changed: true }) }
      .to raise_error(ActiveRecord::StatementInvalid, /invoice revisions are immutable/)
  end

  it "rejects direct SQL deletion of unified invoice revisions" do
    revision = create(:invoice).current_revision

    expect { InvoiceRevision.where(id: revision.id).delete_all }
      .to raise_error(ActiveRecord::StatementInvalid, /invoice revisions are immutable/)
  end
end
