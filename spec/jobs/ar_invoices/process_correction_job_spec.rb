# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe ArInvoices::ProcessCorrectionJob do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel, status: "completed") }
  let(:user) { create(:user, :superadmin) }
  let(:account) { create(:hotel_corporate_account, :direct_bill, hotel: hotel, contact_email: "billing@example.com") }
  let(:folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: account, status: "open") }

  before do
    create(:folio_transaction, booking_folio: folio, amount: 2000)
    expect(Folios::Lifecycle::CloseFolio.call(folio: folio, user: user, settlement_method: "direct_bill")).to be_success
    expect(Folios::Lifecycle::ReopenFolio.call(folio: folio.reload, user: user, reason: "Wrong charge")).to be_success
    create(:folio_transaction, :adjustment, category: "correction", booking_folio: folio, amount: -200)
    expect(Folios::Lifecycle::CloseFolio.call(folio: folio.reload, user: user, send_documents: true)).to be_success
  end

  let(:correction) { ArInvoiceCorrection.last }

  it "completes local-only corrections and queues a single company email with both documents" do
    expect { 2.times { described_class.perform_now(correction.id) } }.to change(NotificationDelivery, :count).by(1)
    expect(correction.reload).to be_completed
    delivery = NotificationDelivery.last
    mail = NotificationMailer.ar_invoice_correction(delivery)
    expect(mail.to).to eq([ "billing@example.com" ])
    expect(mail.attachments.select { |attachment| attachment.filename.end_with?(".pdf") }.size).to eq(2)
    credit_text = PDF::Reader.new(StringIO.new(mail.attachments["#{correction.credit_reference}.pdf"].decoded)).pages.map(&:text).join(" ")
    expect(credit_text).to include(correction.credit_reference, "2,000.00")
    expect(mail.body.encoded).to include("1,800.00")
  end

  it "records provider failures without duplicating the local replacement" do
    allow(EInvoice::ProcessArCorrection).to receive(:call!).and_raise("Provider unavailable")
    expect { described_class.perform_now(correction.id) }.to raise_error("Provider unavailable")
    expect(correction.reload).to be_failed
    expect(correction.error_message).to eq("Provider unavailable")
    expect(folio.reload.ar_invoice.amount).to eq(1800)
    expect(ArInvoice.count).to eq(2)
    expect(NotificationDelivery.count).to eq(0)
    allow(EInvoice::ProcessArCorrection).to receive(:call!).and_return(true)
    expect(ArInvoices::RetryCorrection.call(correction: correction)).to be_success
    described_class.perform_now(correction.id)
    expect(correction.reload).to be_completed
    expect(ArInvoice.count).to eq(2)
  end

  it "waits for validation before creating a delivery" do
    allow(EInvoice::ProcessArCorrection).to receive(:call!).and_return(false)
    described_class.perform_now(correction.id)
    expect(correction.reload).to be_processing
    expect(NotificationDelivery.count).to eq(0)
  end

  it "can retry a failed email without recreating invoices or receipts" do
    described_class.perform_now(correction.id)
    delivery = NotificationDelivery.last
    delivery.update!(status: "failed", error_message: "Mail unavailable")
    expect(ArInvoices::SendCorrection.call(correction: correction.reload)).to be_success
    expect(delivery.reload.status).to eq("pending")
    expect(ArInvoice.count).to eq(2)
  end
end
