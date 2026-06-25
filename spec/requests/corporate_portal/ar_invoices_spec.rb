# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::ArInvoices", type: :request do
  let(:user) { create(:user, :corporate) }

  before { sign_in_as(user) }

  it "lists only invoices belonging to the current corporate account" do
    relationship = create(:hotel_corporate_account, corporate_account: user.account, credit_currency: "MYR")
    visible = create_ar_invoice_for(relationship: relationship, confirmation_token: "CORP-INV-1", folio_number: 7001, amount: 300)
    hidden = create_ar_invoice_for(relationship: create(:hotel_corporate_account), confirmation_token: "CORP-HIDDEN", folio_number: 9001, amount: 999)

    get corporate_ar_invoices_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("AR Invoices")
    expect(response.body).to include("AR-#{visible.invoice_number}")
    expect(response.body).to include("CORP-INV-1")
    expect(response.body).to include(visible.hotel.name)
    expect(response.body).to include("MYR 300.00")
    expect(response.body).not_to include("CORP-HIDDEN")
    expect(response.body).not_to include("AR-#{hidden.invoice_number}")
  end

  it "shows an owned invoice with payment allocations" do
    relationship = create(:hotel_corporate_account, corporate_account: user.account, credit_currency: "MYR")
    invoice = create_ar_invoice_for(relationship: relationship, confirmation_token: "CORP-SHOW", folio_number: 7002, amount: 300)
    payment = create(:ar_payment, hotel_corporate_account: relationship, hotel: relationship.hotel, amount: 100, currency: "MYR", reference_number: "BANK-CORP-1")
    create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 100)

    get corporate_ar_invoice_path(invoice)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("AR-#{invoice.invoice_number}")
    expect(response.body).to include("CORP-SHOW")
    expect(response.body).to include(invoice.hotel.name)
    expect(response.body).to include("BANK-CORP-1")
    expect(response.body).to include("MYR 100.00")
  end

  it "does not expose another corporate account invoice" do
    invoice = create_ar_invoice_for(relationship: create(:hotel_corporate_account), confirmation_token: "CORP-OTHER", folio_number: 9002, amount: 500)

    get corporate_ar_invoice_path(invoice)

    expect(response).to have_http_status(:not_found)
  end

  def create_ar_invoice_for(relationship:, confirmation_token:, folio_number:, amount:)
    booking = create(:booking, hotel: relationship.hotel, confirmation_token: confirmation_token)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, folio_number: folio_number, hotel_corporate_account: relationship)
    create(:ar_invoice,
      hotel: relationship.hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: amount,
      paid_amount: 0,
      outstanding_amount: amount,
      currency: "MYR")
  end
end
