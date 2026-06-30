# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::ArPayments", type: :request do
  let(:user) { create(:user, :corporate) }

  before { sign_in_as(user) }

  it "lists only payments belonging to the current corporate account" do
    relationship = create(:hotel_corporate_account, corporate_account: user.account)
    visible = create(:ar_payment, hotel_corporate_account: relationship, hotel: relationship.hotel, amount: 250, currency: "MYR", reference_number: "PAY-CORP-1")

    # Avoid factory sequence collisions with Faker names on the page
    hidden_hotel = create(:hotel, name: "Hidden Payment Corporate Hotel")
    hidden_relationship = create(:hotel_corporate_account, hotel: hidden_hotel)
    hidden = create(:ar_payment, hotel_corporate_account: hidden_relationship, hotel: hidden_hotel, reference_number: "PAY-HIDDEN-1")

    get corporate_ar_payments_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Payment History")
    expect(response.body).to include("PAY-CORP-1")
    expect(response.body).to include(visible.hotel.name)
    expect(response.body).to include("MYR 250.00")
    expect(response.body).not_to include("PAY-HIDDEN-1")
    expect(response.body).not_to include(hidden_hotel.name)
  end

  it "filters payments by keyword" do
    rel = create(:hotel_corporate_account, corporate_account: user.account)
    h1 = rel.hotel
    h2 = create(:hotel, name: "Sunset Oasis")
    rel2 = create(:hotel_corporate_account, hotel: h2, corporate_account: user.account)

    create(:ar_payment, hotel_corporate_account: rel, hotel: h1, reference_number: "PAYMENT-SEARCH-1")
    create(:ar_payment, hotel_corporate_account: rel2, hotel: h2, reference_number: "PAYMENT-OTHER")

    # Search by reference number
    get corporate_ar_payments_path(query: "search-1")
    expect(response.body).to include("PAYMENT-SEARCH-1")
    expect(response.body).not_to include("PAYMENT-OTHER")

    # Search by hotel name
    get corporate_ar_payments_path(query: "sunset")
    expect(response.body).to include("PAYMENT-OTHER")
    expect(response.body).not_to include("PAYMENT-SEARCH-1")
  end

  it "filters payments by allocation status" do
    rel = create(:hotel_corporate_account, corporate_account: user.account)
    invoice1 = create_invoice(rel)
    invoice2 = create_invoice(rel)

    # 1. Unapplied
    p_unapplied = create(:ar_payment, hotel_corporate_account: rel, hotel: rel.hotel, amount: 100, reference_number: "PAY-UNAPPLIED")

    # 2. Partially allocated
    p_partial = create(:ar_payment, hotel_corporate_account: rel, hotel: rel.hotel, amount: 100, reference_number: "PAY-PARTIAL")
    create(:ar_payment_allocation, ar_payment: p_partial, ar_invoice: invoice1, amount: 40)

    # 3. Fully allocated
    p_fully = create(:ar_payment, hotel_corporate_account: rel, hotel: rel.hotel, amount: 100, reference_number: "PAY-FULLY")
    create(:ar_payment_allocation, ar_payment: p_fully, ar_invoice: invoice2, amount: 100)

    # Filter unapplied
    get corporate_ar_payments_path(status: "unapplied")
    expect(response.body).to include("PAY-UNAPPLIED")
    expect(response.body).not_to include("PAY-PARTIAL")
    expect(response.body).not_to include("PAY-FULLY")

    # Filter partially allocated
    get corporate_ar_payments_path(status: "partially_allocated")
    expect(response.body).to include("PAY-PARTIAL")
    expect(response.body).not_to include("PAY-UNAPPLIED")
    expect(response.body).not_to include("PAY-FULLY")

    # Filter fully allocated
    get corporate_ar_payments_path(status: "fully_allocated")
    expect(response.body).to include("PAY-FULLY")
    expect(response.body).not_to include("PAY-UNAPPLIED")
    expect(response.body).not_to include("PAY-PARTIAL")
  end

  it "filters payments by date range" do
    rel = create(:hotel_corporate_account, corporate_account: user.account)
    create(:ar_payment, hotel_corporate_account: rel, hotel: rel.hotel, reference_number: "PAY-OLD", received_at: 2.months.ago)
    create(:ar_payment, hotel_corporate_account: rel, hotel: rel.hotel, reference_number: "PAY-NEW", received_at: 1.day.ago)

    get corporate_ar_payments_path(received_from: 1.week.ago.to_date.iso8601)
    expect(response.body).to include("PAY-NEW")
    expect(response.body).not_to include("PAY-OLD")
  end

  it "displays summary metrics on index page" do
    rel = create(:hotel_corporate_account, corporate_account: user.account)
    invoice = create_invoice(rel)

    # Received this month
    p1 = create(:ar_payment, hotel_corporate_account: rel, hotel: rel.hotel, amount: 200, currency: "MYR", received_at: Time.current.to_date)
    # Allocation
    create(:ar_payment_allocation, ar_payment: p1, ar_invoice: invoice, amount: 120)

    get corporate_ar_payments_path

    expect(response.body).to include("Received This Month")
    expect(response.body).to include("MYR 200.00")
    expect(response.body).to include("Allocated This Month")
    expect(response.body).to include("MYR 120.00")
    expect(response.body).to include("Total Unapplied")
    expect(response.body).to include("MYR 80.00")
    expect(response.body).to include("Needs Allocation")
  end

  it "shows allocation history and reversal logs on payment show page" do
    rel = create(:hotel_corporate_account, corporate_account: user.account)
    payment = create(:ar_payment, hotel_corporate_account: rel, hotel: rel.hotel, amount: 200, currency: "MYR", reference_number: "PAY-12345")
    invoice1 = create_invoice(rel)
    invoice2 = create_invoice(rel)

    # Active allocation
    create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice1, amount: 120)
    # Reversed allocation
    alloc = create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice2, amount: 80)
    create(:ar_payment_allocation_reversal, ar_payment_allocation: alloc, reversed_by: create(:user, name: "Finance Admin"), reason: "Typo in allocation")

    # Request legacy payment details
    get corporate_ar_payment_path(payment, legacy: true)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Payment Record")
    expect(response.body).to include("PAY-12345")
    expect(response.body).to include("Allocation ledger")
    expect(response.body).to include(invoice1.formatted_invoice_number)
    expect(response.body).to include(invoice2.formatted_invoice_number)
    expect(response.body).to include("Reversed")
    expect(response.body).to include("Typo in allocation")
    expect(response.body).to include("Finance Admin")
  end

  it "shows only active relationships on pay invoices" do
    user.account.hotel_corporate_accounts.reload
    active_hotel = create(:hotel, name: "Active Billing Corporate Hotel")
    suspended_hotel = create(:hotel, name: "Suspended Billing Corporate Hotel")
    active_relationship = create(:hotel_corporate_account, hotel: active_hotel, corporate_account: user.account, status: "active")
    suspended_relationship = create(:hotel_corporate_account, hotel: suspended_hotel, corporate_account: user.account, status: "active")
    create_invoice(active_relationship)
    create_invoice(suspended_relationship)
    suspended_relationship.update!(status: "suspended", suspended_at: Time.current)

    get pay_invoices_corporate_ar_payments_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Active Billing Corporate Hotel")
    expect(response.body).not_to include("Suspended Billing Corporate Hotel")
  end

  it "rejects review for a suspended relationship" do
    user.account.hotel_corporate_accounts.reload
    relationship = create(:hotel_corporate_account, corporate_account: user.account, status: "active")
    invoice = create_invoice(relationship)
    relationship.update!(status: "suspended", suspended_at: Time.current)

    post review_corporate_ar_payments_path, params: {
      corporate_ar_payment: {
        hotel_corporate_account_id: relationship.id,
        invoice_ids: [ invoice.id ],
        amount: "100.00",
        currency: invoice.currency,
        gateway: "razorpay"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Corporate relationship is not available for payment.")
    expect(CorporateArPaymentIntent.count).to eq(0)
  end

  it "creates an intent and renders review for active relationships" do
    user.account.hotel_corporate_accounts.reload
    relationship = create(:hotel_corporate_account, corporate_account: user.account)
    create(:payment_setting, settable: relationship.hotel, gateway: "razorpay", api_key: "key", secret_key: "secret", status: "active")
    invoice = create_invoice(relationship)

    expect do
      post review_corporate_ar_payments_path, params: {
        corporate_ar_payment: {
          hotel_corporate_account_id: relationship.id,
          invoice_ids: [ invoice.id ],
          amount: "100.00",
          currency: invoice.currency,
          gateway: "razorpay"
        }
      }
    end.to change(CorporateArPaymentIntent, :count).by(1)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Review Payment")
    expect(response.body).to include(invoice.formatted_invoice_number)
  end

  it "rejects checkout when relationship is suspended after review" do
    user.account.hotel_corporate_accounts.reload
    relationship = create(:hotel_corporate_account, corporate_account: user.account)
    create(:payment_setting, settable: relationship.hotel, gateway: "razorpay", api_key: "key", secret_key: "secret", status: "active")
    intent = create(:corporate_ar_payment_intent, hotel_corporate_account: relationship, hotel: relationship.hotel, corporate_account: user.account, user: user)
    relationship.update!(status: "suspended", suspended_at: Time.current)

    post checkout_session_corporate_ar_payments_path, params: { intent_id: intent.id }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["error"]).to eq("Corporate relationship is not available for payment.")
  end

  def create_invoice(relationship)
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: 100, paid_amount: 0, outstanding_amount: 100, currency: relationship.hotel.default_currency)
  end
end
