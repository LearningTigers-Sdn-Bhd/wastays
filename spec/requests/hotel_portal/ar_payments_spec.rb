# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ArPayments", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_reports) { Permission.find_or_create_by!(slug: "view_reports") { |permission| permission.name = "View Reports" } }
  let(:manage_ar_payments) { Permission.find_or_create_by!(slug: "manage_ar_payments") { |permission| permission.name = "Manage AR Payments" } }

  before do
    role.permissions << [ view_reports, manage_ar_payments ]
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "renders the redesigned index with metrics, filters, statuses, and scoped rows" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 500, reference_number: "BANK-AR-500")
    hidden = create(:ar_payment, hotel: other_hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: other_hotel), amount: 999, reference_number: "BANK-HIDDEN")

    get hotel_ar_payments_path(hotel)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Received This Month")
    expect(response.body).to include("Total Unapplied")
    expect(response.body).to include("Needs Allocation")
    expect(response.body).to include("BANK-AR-500")
    expect(response.body).to include("Unapplied")
    expect(response.body).not_to include(hidden.reference_number)
    expect(response.body).to include(hotel_ar_payment_path(hotel, payment))
  end

  it "filters by query, account, date, and allocation status" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 200, received_at: Date.current, reference_number: "FILTER-ME")
    create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 300, reference_number: "HIDE-ME")

    get hotel_ar_payments_path(hotel), params: {
      query: "FILTER-ME",
      hotel_corporate_account_id: payment.hotel_corporate_account_id,
      received_from: Date.current.iso8601,
      received_to: Date.current.iso8601,
      status: "unapplied"
    }

    expect(response.body).to include("FILTER-ME")
    expect(response.body).not_to include("HIDE-ME")
  end

  it "shows payment details, active and reversed history, and eligible invoices" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 500, notes: "Bank receipt")
    invoice = create_invoice(relationship: payment.hotel_corporate_account, amount: 500)
    allocation = create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 100)
    create(:ar_payment_allocation_reversal, ar_payment_allocation: allocation, reversed_by: user, reason: "Wrong invoice")

    get hotel_ar_payment_path(hotel, payment)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(payment.reference_number)
    expect(response.body).to include("Payment record")
    expect(response.body).to include("Allocation ledger")
    expect(response.body).to include("Wrong invoice")
    expect(response.body).to include("Open invoices")
    expect(response.body).to include("AR-#{invoice.invoice_number}")
  end

  it "records a fully unapplied payment" do
    expect {
      post hotel_ar_payments_path(hotel), params: {
        ar_payment: {
          hotel_corporate_account_id: create(:hotel_corporate_account, hotel: hotel).id,
          amount: "500.00",
          currency: hotel.default_currency,
          reference_number: "UNAPPLIED-1",
          received_at: Date.current.iso8601,
          payment_method: "bank_transfer"
        },
        allocations: {}
      }
    }.to change(ArPayment, :count).by(1)

    expect(response).to redirect_to(hotel_ar_payment_path(hotel, ArPayment.last))
    expect(ArPayment.last.unallocated_amount).to eq(500.to_d)
  end

  it "refreshes eligible invoices for the selected corporate account" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    invoice = create_invoice(relationship: relationship, amount: 250)
    hidden_relationship = create(:hotel_corporate_account, hotel: hotel)
    hidden_invoice = create_invoice(relationship: hidden_relationship, amount: 300)

    get eligible_invoices_hotel_ar_payments_path(hotel), params: { hotel_corporate_account_id: relationship.id }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("AR-#{invoice.invoice_number}")
    expect(response.body).not_to include("AR-#{hidden_invoice.invoice_number}")
    expect(response.body).to include("ar_payment_invoice_allocations")
  end

  it "allocates remaining balance and reverses the allocation" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 400)
    invoice = create_invoice(relationship: payment.hotel_corporate_account, amount: 500)

    post hotel_ar_payment_allocations_path(hotel, payment), params: { allocations: { invoice.id => "400.00" } }

    allocation = payment.ar_payment_allocations.last
    expect(response).to redirect_to(hotel_ar_payment_path(hotel, payment))
    expect(invoice.reload.outstanding_amount).to eq(100.to_d)

    post hotel_ar_payment_allocation_reversal_path(hotel, payment, allocation), params: { reason: "Wrong invoice" }

    expect(response).to redirect_to(hotel_ar_payment_path(hotel, payment))
    expect(invoice.reload.outstanding_amount).to eq(500.to_d)
    expect(allocation.reload).to be_reversed
  end

  it "keeps view_reports read-only" do
    role.permissions.delete(manage_ar_payments)
    relationship = create(:hotel_corporate_account, hotel: hotel)

    get hotel_ar_payments_path(hotel)
    expect(response).to have_http_status(:success)
    expect(response.body).not_to include("Record Received Payment")

    post hotel_ar_payments_path(hotel), params: {
      ar_payment: {
        hotel_corporate_account_id: relationship.id,
        amount: "100.00",
        currency: hotel.default_currency,
        reference_number: "DENIED",
        received_at: Date.current.iso8601,
        payment_method: "cash"
      }
    }
    expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)

    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 100)
    invoice = create_invoice(relationship: relationship, amount: 100)
    post hotel_ar_payment_allocations_path(hotel, payment), params: { allocations: { invoice.id => "100.00" } }
    expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
  end

  def create_invoice(relationship:, amount:)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: hotel.default_currency)
  end
end
