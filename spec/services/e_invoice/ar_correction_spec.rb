# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe "AR invoice e-invoice correction" do
  let(:hotel) { create(:hotel, status: "live", tin: "C9988776655", ssm_number: "202399887766") }
  let!(:setting) { create(:e_invoice_setting, hotel: hotel) }
  let(:booking) { create(:booking, hotel: hotel, currency: "MYR", status: "completed") }
  let(:user) { create(:user, :superadmin) }
  let(:account) { create(:hotel_corporate_account, :direct_bill, hotel: hotel) }
  let(:folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: account, status: "open") }
  let(:buyer) do
    { "name" => account.corporate_account.name, "tin" => "C12345678901", "government_id" => "202301012345",
      "document_type" => "brn", "contact_email" => "billing@example.com", "contact_phone" => "+60123456789",
      "billing_address" => { "city" => "Kota Kinabalu", "country_code" => "MYS", "state_code" => "12",
                             "postal_code" => "88000", "address_line1" => "123 Company Street" } }
  end
  let(:original) { folio.reload.ar_invoice.invoice }
  let(:original_submission) do
    create(:e_invoice_submission, hotel: hotel, booking: booking, invoice: original, status: "valid",
      document_type: "01", internal_id: original.invoice_reference, uuid: "original-uuid", buyer_snapshot: buyer)
  end
  let(:client) { instance_double(MyInvois::Client) }

  before do
    create(:folio_transaction, booking_folio: folio, amount: 2000)
    expect(Folios::Lifecycle::CloseFolio.call(folio: folio, user: user, settlement_method: "direct_bill")).to be_success
    allow(MyInvois::ClientFactory).to receive(:build).and_return(client)
  end

  def correct
    original_submission
    expect(Folios::Lifecycle::ReopenFolio.call(folio: folio.reload, user: user, reason: "Wrong charge")).to be_success
    create(:folio_transaction, :adjustment, category: "correction", booking_folio: folio, amount: -200)
    expect(Folios::Lifecycle::CloseFolio.call(folio: folio.reload, user: user, settlement_method: "direct_bill", send_documents: true)).to be_success
    ArInvoiceCorrection.last
  end

  it "builds a company credit with the original UUID and invoice snapshot, not room totals" do
    correction = correct
    submission = EInvoiceSubmission.new(document_type: "02", internal_id: correction.credit_reference)
    document = EInvoice::ArCorrectionDocumentBuilder.new(correction: correction, submission: submission,
      original_submission: original_submission).build
    body = JSON.parse(Base64.strict_decode64(document[:document])).fetch("Invoice").first
    expect(body.dig("BillingReference", 0, "InvoiceDocumentReference", 0, "UUID", 0, "_")).to eq("original-uuid")
    expect(body.dig("LegalMonetaryTotal", 0, "PayableAmount", 0, "_")).to eq(2000)
    expect(body.dig("AccountingCustomerParty", 0, "Party", 0, "PartyLegalEntity", 0, "RegistrationName", 0, "_")).to eq(buyer["name"])
    expect(body.dig("InvoiceTypeCode", 0, "_")).to eq("02")
  end

  it "validates the credit before sending the replacement and only completes after both validate" do
    correction = correct
    allow(client).to receive(:submit_documents).and_return(
      { "acceptedDocuments" => [ { "uuid" => "credit-uuid" } ], "submissionUid" => "credit-submission" },
      { "acceptedDocuments" => [ { "uuid" => "replacement-uuid" } ], "submissionUid" => "replacement-submission" }
    )
    allow(client).to receive(:get_document_details).and_return({ "status" => "Valid", "longId" => "ready" })
    expect(EInvoice::ProcessArCorrection.call!(correction: correction)).to be(false)
    expect(correction.e_invoice_submissions.pluck(:document_type)).to eq([ "02" ])
    expect(EInvoice::ProcessArCorrection.call!(correction: correction)).to be(false)
    expect(EInvoice::ProcessArCorrection.call!(correction: correction)).to be(true)
    expect(client).to have_received(:submit_documents).twice
    expect(EInvoice::ProcessArCorrection.call!(correction: correction)).to be(true)
    expect(client).to have_received(:submit_documents).twice
  end

  it "never submits again after a timeout with uncertain acceptance" do
    correction = correct
    allow(client).to receive(:submit_documents).and_raise(Timeout::Error)
    expect { EInvoice::ProcessArCorrection.call!(correction: correction) }.to raise_error(Timeout::Error)
    expect { EInvoice::ProcessArCorrection.call!(correction: correction) }.to raise_error(/uncertain/)
    expect(client).to have_received(:submit_documents).once
  end

  it "rejects ambiguous booking-level originals instead of correcting a guest document" do
    create(:e_invoice_submission, hotel: hotel, booking: booking, status: "valid", uuid: "guest-uuid",
      buyer_snapshot: buyer.merge("name" => "Guest"))
    result = Folios::Lifecycle::ReopenFolio.call(folio: folio.reload, user: user, reason: "Wrong charge")
    expect(result.error).to include("not linked")
    expect(folio.reload).to be_closed
    expect(ArInvoiceCorrection.count).to eq(0)
  end

  it "keeps legacy guest submission uniqueness but permits successive company corrections" do
    correction = correct
    create(:e_invoice_submission, hotel: hotel, booking: booking, ar_invoice_correction: correction,
      document_scenario: "company_invoice_correction", invoice: original, document_type: "02")
    expect { original_submission.update!(supplier_name: "Original issuer") }.not_to raise_error
  end
  it "preserves captured SST on the full cancellation credit" do
    # Issue a source document with a posted tax line rather than using booking estimates.
    Folios::Lifecycle::ReopenFolio.call(folio: folio.reload, user: user, reason: "Add original tax")
    create(:folio_transaction, booking_folio: folio, amount: 160, category: "tax",
      description: "SST", metadata: { tax_line: { type: "sst", rate: "8", amount: "160" } })
    expect(Folios::Lifecycle::CloseFolio.call(folio: folio.reload, user: user)).to be_success
    previous = ArInvoiceCorrection.last
    ArInvoices::ProcessCorrectionJob.perform_now(previous.id)
    submission = create(:e_invoice_submission, hotel: hotel, booking: booking, invoice: folio.ar_invoice.invoice,
      status: "valid", uuid: "tax-original", internal_id: folio.ar_invoice.formatted_invoice_number, buyer_snapshot: buyer)
    expect(Folios::Lifecycle::ReopenFolio.call(folio: folio.reload, user: user, reason: "Correct taxed charges")).to be_success
    create(:folio_transaction, booking_folio: folio, amount: 100)
    expect(Folios::Lifecycle::CloseFolio.call(folio: folio.reload, user: user)).to be_success
    correction = ArInvoiceCorrection.last
    document = EInvoice::ArCorrectionDocumentBuilder.new(correction: correction,
      submission: EInvoiceSubmission.new(document_type: "02", internal_id: correction.credit_reference),
      original_submission: submission).build
    body = JSON.parse(Base64.strict_decode64(document[:document])).fetch("Invoice").first
    expect(body.dig("TaxTotal", 0, "TaxAmount", 0, "_")).to eq(160)
    expect(body.dig("LegalMonetaryTotal", 0, "TaxExclusiveAmount", 0, "_")).to eq(2000)
    expect(body.dig("LegalMonetaryTotal", 0, "TaxInclusiveAmount", 0, "_")).to eq(2160)
    expect(body.dig("TaxTotal", 0, "TaxSubtotal", 0, "TaxCategory", 0, "ID", 0, "_")).to eq("02")
  end

  it "retries an explicit provider rejection using the same correction without reposting AR" do
    correction = correct
    allow(client).to receive(:submit_documents).and_return({ "rejectedDocuments" => [ { "error" => "Invalid" } ] })
    expect { EInvoice::ProcessArCorrection.call!(correction: correction) }.to raise_error(/rejected/)
    correction.update!(status: "failed", error_message: "Rejected")
    expect(ArInvoices::RetryCorrection.call(correction: correction)).to be_success
    note = correction.e_invoice_submissions.first
    expect(note.reload.status).to eq("pending")
    expect(note.error_details["attempt_history"].size).to eq(1)
    expect(ArInvoice.count).to eq(2)
  end

  it "renders correction e-invoices from their own documents after validation" do
    correction = correct
    note = create(:e_invoice_submission, hotel: hotel, booking: booking, invoice: original,
      ar_invoice_correction: correction, document_scenario: "company_invoice_correction",
      document_type: "02", status: "valid", uuid: "credit-uuid", internal_id: correction.credit_reference,
      buyer_snapshot: buyer)
    text = PDF::Reader.new(StringIO.new(EInvoicePdfService.new(booking, submission: note).generate)).pages.map(&:text).join(" ")
    expect(text).to include(correction.credit_reference, "credit-uuid", "2,000.00")
  end
end
