# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261009100000_add_ar_invoice_corrections")

RSpec.describe AddArInvoiceCorrections do
  it "keeps uniqueness for current invoices while allowing preserved canceled documents" do
    connection = ActiveRecord::Base.connection
    invoice_index = connection.indexes(:invoices).find { |index| index.name == "idx_invoices_current_folio" }
    receivable_index = connection.indexes(:ar_invoices).find { |index| index.name == "idx_ar_invoices_current_folio" }
    expect(invoice_index.unique).to be(true)
    expect(invoice_index.where).to include("voided")
    expect(receivable_index.unique).to be(true)
    expect(receivable_index.where).to include("void")
  end

  it "retains the legacy booking uniqueness index and separately constrains correction submissions" do
    indexes = ActiveRecord::Base.connection.indexes(:e_invoice_submissions)
    legacy = indexes.find { |index| index.name == "index_e_invoice_submissions_on_booking_scenario_type" }
    correction = indexes.find { |index| index.name == "idx_e_invoice_correction_type" }
    expect(legacy.where).to include("ar_invoice_correction_id IS NULL")
    expect(correction.unique).to be(true)
    expect(correction.columns).to eq(%w[ar_invoice_correction_id document_type])
  end
end
