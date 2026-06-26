# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::ArInvoices", type: :request do
  let(:user) { create(:user, :corporate) }
  let(:relationship) { create(:hotel_corporate_account, corporate_account: user.account, credit_currency: "MYR") }

  before { sign_in_as(user) }

  describe "GET /corporate/invoices (index)" do
    it "renders the metrics bar and invoice table" do
      create_ar_invoice_for(relationship: relationship, confirmation_token: "BK-METRIC", folio_number: 5001, amount: 350)

      get corporate_ar_invoices_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("AR Invoices")
      expect(response.body).to include("Open AR")
      expect(response.body).to include("Due Soon")
      expect(response.body).to include("MYR 350.00")
    end

    it "only shows invoices belonging to the current corporate account" do
      visible = create_ar_invoice_for(relationship: relationship, confirmation_token: "CORP-INV-1", folio_number: 7001, amount: 300)
      _hidden = create_ar_invoice_for(relationship: create(:hotel_corporate_account), confirmation_token: "CORP-HIDDEN", folio_number: 9001, amount: 999)

      get corporate_ar_invoices_path

      expect(response.body).to include(visible.formatted_invoice_number)
      expect(response.body).not_to include("CORP-HIDDEN")
    end

    it "filters by status" do
      open_inv = create_ar_invoice_for(relationship: relationship, confirmation_token: "BK-OPEN", folio_number: 5002, amount: 100, status: "open")
      paid_inv = create_ar_invoice_for(relationship: relationship, confirmation_token: "BK-PAID", folio_number: 5003, amount: 100, status: "paid", paid_amount: 100, outstanding_amount: 0)

      get corporate_ar_invoices_path, params: { status: "open" }

      expect(response.body).to include(open_inv.formatted_invoice_number)
      expect(response.body).not_to include(paid_inv.formatted_invoice_number)
    end

    it "filters by keyword (booking ref)" do
      match = create_ar_invoice_for(relationship: relationship, confirmation_token: "FIND-ME", folio_number: 5004, amount: 100)
      other = create_ar_invoice_for(relationship: relationship, confirmation_token: "DONT-FIND", folio_number: 5005, amount: 100)

      get corporate_ar_invoices_path, params: { query: "FIND-ME" }

      expect(response.body).to include(match.formatted_invoice_number)
      expect(response.body).not_to include(other.formatted_invoice_number)
    end

    it "includes a Pay Invoices link" do
      get corporate_ar_invoices_path

      expect(response.body).to include(pay_invoices_corporate_ar_payments_path)
    end
  end

  describe "GET /corporate/invoices/:id (show)" do
    it "shows an owned invoice with payment allocations" do
      invoice = create_ar_invoice_for(relationship: relationship, confirmation_token: "CORP-SHOW", folio_number: 7002, amount: 300)
      payment = create(:ar_payment, hotel_corporate_account: relationship, hotel: relationship.hotel,
                       amount: 100, currency: "MYR", reference_number: "BANK-CORP-1")
      create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 100)

      get corporate_ar_invoice_path(invoice)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(invoice.formatted_invoice_number)
      expect(response.body).to include(ERB::Util.html_escape(invoice.hotel.name))
      expect(response.body).to include("BANK-CORP-1")
      expect(response.body).to include("MYR 100.00")
    end

    it "renders the details section with payment terms and direct bill source" do
      invoice = create_ar_invoice_for(
        relationship: relationship, confirmation_token: "BK-TERMS", folio_number: 7003, amount: 200,
        metadata: { payment_terms_days: 30, direct_bill_closed_at: "2026-06-01T00:00:00Z" }
      )

      get corporate_ar_invoice_path(invoice)

      expect(response.body).to include("Payment Terms")
      expect(response.body).to include("Net 30 days")
      expect(response.body).to include("Direct Bill Source")
      expect(response.body).to include("Folio close")
    end

    it "shows the Pay Invoice CTA when the invoice has an outstanding balance" do
      invoice = create_ar_invoice_for(relationship: relationship, confirmation_token: "BK-CTA", folio_number: 7004, amount: 200)

      get corporate_ar_invoice_path(invoice)

      expect(response.body).to include("Pay Invoice")
      expect(response.body).to include(pay_invoices_corporate_ar_payments_path(hotel_corporate_account_id: relationship.id))
    end

    it "does not show the Pay Invoice CTA when the invoice is fully paid" do
      invoice = create_ar_invoice_for(
        relationship: relationship, confirmation_token: "BK-PAID-CTA", folio_number: 7005,
        amount: 200, paid_amount: 200, outstanding_amount: 0, status: "paid"
      )

      get corporate_ar_invoice_path(invoice)

      # The nav bar always shows "Pay Invoices" — assert the show-page CTA URL with hotel_corporate_account_id is absent
      expect(response.body).not_to include(pay_invoices_corporate_ar_payments_path(hotel_corporate_account_id: relationship.id))
    end

    it "returns 404 for another corporate account's invoice" do
      invoice = create_ar_invoice_for(relationship: create(:hotel_corporate_account), confirmation_token: "CORP-OTHER", folio_number: 9002, amount: 500)

      get corporate_ar_invoice_path(invoice)

      expect(response).to have_http_status(:not_found)
    end
  end

  def create_ar_invoice_for(relationship:, confirmation_token:, folio_number:, amount:,
                            paid_amount: 0, outstanding_amount: nil, status: "open", metadata: {})
    outstanding_amount ||= amount - paid_amount
    booking = create(:booking, hotel: relationship.hotel, confirmation_token: confirmation_token)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel,
                   folio_number: folio_number, hotel_corporate_account: relationship)
    create(:ar_invoice,
           hotel: relationship.hotel,
           booking_folio: folio,
           hotel_corporate_account: relationship,
           amount: amount,
           paid_amount: paid_amount,
           outstanding_amount: outstanding_amount,
           currency: "MYR",
           status: status,
           metadata: metadata)
  end
end
