# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ArInvoices", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_reports) { Permission.find_or_create_by!(slug: "view_reports") { |permission| permission.name = "View Reports" } }

  before do
    role.permissions << view_reports
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/ar-invoices" do
    it "renders hotel scoped AR invoice ledger rows" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-AR-1", folio_number: 501, amount: 300)
      hidden = create_ar_invoice_for(hotel: other_hotel, confirmation_token: "BK-HIDDEN", folio_number: 901, amount: 999)

      get hotel_ar_invoices_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("AR Invoices")
      expect(response.body).to include("AR-#{invoice.invoice_number}")
      expect(response.body).to include("BK-AR-1")
      expect(response.body).to include(invoice.corporate_account.name)
      expect(response.body).to include("MYR 300.00")
      expect(response.body).not_to include("BK-HIDDEN")
      expect(response.body).not_to include("AR-#{hidden.invoice_number}")
    end

    it "requires view reports permission" do
      role.permissions.delete(view_reports)

      get hotel_ar_invoices_path(hotel)

      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
    end
  end

  describe "GET /hotel/:hotel_id/accounts-receivable/payments" do
    it "renders hotel scoped AR payment rows" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-PAY-IDX", folio_number: 901, amount: 200)
      payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: invoice.hotel_corporate_account, amount: 100, currency: "MYR", reference_number: "BANK-IDX-1")
      create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 100)

      get hotel_ar_payments_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("AR Payments")
      expect(response.body).to include("BANK-IDX-1")
      expect(response.body).to include(invoice.corporate_account.name)
      expect(response.body).to include("MYR 100.00")
    end
  end

  describe "legacy Accounts Receivable redirects" do
    it "redirects old AR invoice and payment paths" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-REDIR", folio_number: 902, amount: 100)

      get "/hotel/#{hotel.slug}/ar-invoices"
      expect(response).to redirect_to("/hotel/#{hotel.slug}/accounts-receivable/invoices")

      get "/hotel/#{hotel.slug}/ar-invoices/#{invoice.id}"
      expect(response).to redirect_to("/hotel/#{hotel.slug}/accounts-receivable/invoices/#{invoice.id}")

      get "/hotel/#{hotel.slug}/ar-payments/new"
      expect(response).to redirect_to("/hotel/#{hotel.slug}/accounts-receivable/payments/new")
    end
  end

  describe "GET /hotel/:hotel_id/ar-invoices/:id" do
    it "renders source booking, folio, corporate account, due date, and outstanding balance" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-AR-SHOW", folio_number: 701, amount: 450)

      get hotel_ar_invoice_path(hotel, invoice)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("AR-#{invoice.invoice_number}")
      expect(response.body).to include("BK-AR-SHOW")
      expect(response.body).to include(invoice.booking_folio.folio_reference_display)
      expect(response.body).to include(invoice.corporate_account.name)
      expect(response.body).to include(invoice.due_on.strftime("%d %b %Y"))
      expect(response.body).to include("MYR 450.00")
      expect(response.body).to include("Outstanding")
    end

    it "does not expose invoices from another hotel" do
      invoice = create_ar_invoice_for(hotel: other_hotel, confirmation_token: "BK-OTHER", folio_number: 801, amount: 300)

      get hotel_ar_invoice_path(hotel, invoice)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /hotel/:hotel_id/ar-payments/new" do
    it "renders a corporate payment form for an invoice account" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-PAY-FORM", folio_number: 811, amount: 300)

      get new_hotel_ar_payment_path(hotel, ar_invoice_id: invoice.id, hotel_corporate_account_id: invoice.hotel_corporate_account_id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Record Corporate Payment")
      expect(response.body).to include(invoice.corporate_account.name)
      expect(response.body).to include("AR-#{invoice.invoice_number}")
      expect(response.body).to include("allocations[#{invoice.id}]")
      expect(response.body).to include("Reference Number")
      expect(response.body).to include("Received At")
    end
  end

  describe "POST /hotel/:hotel_id/ar-payments" do
    it "records one corporate payment across multiple invoices" do
      first = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-PAY-1", folio_number: 821, amount: 100)
      second = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-PAY-2", folio_number: 822, amount: 200, relationship: first.hotel_corporate_account)

      expect {
        post hotel_ar_payments_path(hotel), params: {
          ar_payment: {
            hotel_corporate_account_id: first.hotel_corporate_account_id,
            amount: "250.00",
            currency: "MYR",
            reference_number: "BANK-MULTI-1",
            received_at: Date.current.iso8601,
            payment_method: "bank_transfer"
          },
          allocations: {
            first.id.to_s => "100.00",
            second.id.to_s => "150.00"
          }
        }
      }.to change(ArPayment, :count).by(1)
        .and change(ArPaymentAllocation, :count).by(2)

      expect(response).to redirect_to(hotel_ar_invoices_path(hotel))
      expect(first.reload).to be_paid
      expect(second.reload).to have_attributes(paid_amount: 150.to_d, outstanding_amount: 50.to_d, status: "partially_paid")
    end

    it "rejects over-allocation beyond payment amount" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-PAY-OVER", folio_number: 823, amount: 100)

      expect {
        post hotel_ar_payments_path(hotel), params: {
          ar_payment: {
            hotel_corporate_account_id: invoice.hotel_corporate_account_id,
            ar_invoice_id: invoice.id,
            amount: "50.00",
            currency: "MYR",
            reference_number: "BANK-OVER-1",
            received_at: Date.current.iso8601,
            payment_method: "bank_transfer"
          },
          allocations: { invoice.id.to_s => "80.00" }
        }
      }.not_to change(ArPayment, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Allocation total cannot exceed payment amount.")
      expect(invoice.reload.outstanding_amount).to eq(100.to_d)
    end
  end

  def create_ar_invoice_for(hotel:, confirmation_token:, folio_number:, amount:, relationship: nil)
    booking = create(:booking, hotel: hotel, confirmation_token: confirmation_token)
    relationship ||= create(:hotel_corporate_account, hotel: hotel, direct_bill_enabled: true)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_number: folio_number, hotel_corporate_account: relationship)
    create(:ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: amount,
      paid_amount: 0,
      outstanding_amount: amount,
      currency: "MYR")
  end
end
