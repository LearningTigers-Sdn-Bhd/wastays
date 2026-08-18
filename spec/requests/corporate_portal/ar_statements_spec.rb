# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::ArStatements", type: :request do
  let(:user) { create(:user, :corporate) }

  before do
    sign_in_as(user)
    user.account.hotel_corporate_accounts.reload
    allow_any_instance_of(Hotel).to receive(:current_business_date).and_return(Date.new(2026, 6, 30))
  end

  it "lists only hotel relationships belonging to the current corporate account" do
    relationship = create(:hotel_corporate_account, corporate_account: user.account, hotel: create(:hotel, name: "Visible Statement Hotel"))
    invoice = create_invoice(relationship, amount: 300, issued_on: Date.new(2026, 6, 1))
    payment = create(:ar_payment, hotel: relationship.hotel, hotel_corporate_account: relationship, amount: 100, received_at: Date.new(2026, 6, 5))
    create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 40)

    hidden_hotel = create(:hotel, name: "Hidden Statement Hotel")
    hidden_relationship = create(:hotel_corporate_account, hotel: hidden_hotel)

    get corporate_ar_statements_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Visible Statement Hotel")
    expect(response.body).to include("MYR 200.00", "MYR 60.00")
    expect(response.body).not_to include("Hidden Statement Hotel")
    expect(response.body).to include(corporate_ar_statement_path(relationship))
    expect(response.body).not_to include(corporate_ar_statement_path(hidden_relationship))
  end

  it "renders the default month-to-business-date statement for a hotel relationship" do
    relationship = create(:hotel_corporate_account, corporate_account: user.account, hotel: create(:hotel, name: "Statement Show Hotel"))
    create_invoice(relationship, amount: 250, issued_on: Date.new(2026, 6, 5), currency: "MYR")
    create_invoice(relationship, amount: 75, issued_on: Date.new(2026, 6, 8), currency: "USD")

    get corporate_ar_statement_path(relationship)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Statement Show Hotel")
    expect(response.body).to include("MYR 250.00")

    get corporate_ar_statement_path(relationship), params: { start_date: "2026-06-01", end_date: "2026-06-30", currency: "USD" }

    expect(response.body).to include("USD 75.00")
    expect(response.body).not_to include("MYR 250.00")
  end

  it "exports a statement with a readable hotel and period filename" do
    hotel = create(:hotel, name: "Seaview Resort")
    relationship = create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel)
    create_invoice(relationship, amount: 250, issued_on: Date.new(2026, 6, 5))

    filename = "account-statement-seaview-resort-2026-06-01-2026-06-30-MYR.pdf"
    get pdf_corporate_ar_statement_path(relationship, filename), params: {
      start_date: "2026-06-01",
      end_date: "2026-06-30",
      currency: "MYR"
    }

    expect(response).to have_http_status(:success)
    expect(response.headers["Content-Disposition"]).to include(
      "account-statement-seaview-resort-2026-06-01-2026-06-30-MYR.pdf"
    )
    expect(URI.parse(pdf_corporate_ar_statement_path(relationship, filename)).path).to end_with("/#{filename}")
  end

  it "does not allow viewing a statement for another corporate account's relationship" do
    other_relationship = create(:hotel_corporate_account)

    get corporate_ar_statement_path(other_relationship)

    expect(response).to have_http_status(:not_found)
  end

  def create_invoice(relationship, amount:, issued_on:, currency: "MYR")
    booking = create(:booking, hotel: relationship.hotel, currency: currency)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship, currency: currency)
    create(
      :ar_invoice,
      hotel: relationship.hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: amount,
      outstanding_amount: amount,
      currency: currency,
      issued_on: issued_on,
      due_on: issued_on + 30.days
    )
  end
end
