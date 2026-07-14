# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ArInvoices", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_reports) { Permission.find_or_create_by!(slug: "view_reports") { |permission| permission.name = "View Reports" } }
  let(:manage_ar_payments) { Permission.find_or_create_by!(slug: "manage_ar_payments") { |permission| permission.name = "Manage AR Payments" } }

  before do
    role.permissions << [ view_reports, manage_ar_payments ]
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
      expect(response.body).to include(invoice.formatted_invoice_number)
      expect(response.body).to include("BK-AR-1")
      expect(response.body).to include(invoice.corporate_account.name)
      expect(response.body).to include("MYR 300.00")
      expect(response.body).not_to include("BK-HIDDEN")
      expect(response.body).not_to include(hidden.formatted_invoice_number)
    end

    it "renders the redesigned header, metrics, single-line columns, and row actions" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-ACTIONS", folio_number: 511, amount: 320)

      get hotel_ar_invoices_path(hotel)

      document = Nokogiri::HTML(response.body)
      headings = document.css("thead th").map { |heading| heading.text.squish }
      row = document.at_css("[data-testid='ar-invoice-row-#{invoice.id}']")

      expect(response.body).to include("AR Invoices")
      expect(response.body).not_to include("Accounts Receivable Invoices (AR Invoices)")
      expect(response.body).to include("Track Direct Bill invoices, due dates, and outstanding corporate balances.")
      expect(response.body).to include("Record Received Payment")
      expect(response.body).to include("Open AR")
      expect(response.body).to include("Overdue")
      expect(response.body).to include("Due Soon")
      expect(response.body).to include("Paid This Month")
      expect(response.body).to include("All corporate accounts")
      expect(headings).to eq([ "Invoice", "Status", "Corporate Account", "Source", "Issued", "Due", "Outstanding", "Action" ])
      expect(headings).not_to include("Amount", "Paid")
      expect(row["role"]).to eq("link")
      expect(row["tabindex"]).to eq("0")
      expect(row["data-controller"]).to eq("clickable-row")
      expect(row["data-clickable-row-url-value"]).to eq(hotel_ar_invoice_path(hotel, invoice))
      expect(row.text.squish).to include("Booking BK-ACTIONS · Folio #{invoice.booking_folio.folio_reference_display}")
      expect(row.text.squish).to include("MYR 320.00")
      expect(row.text.squish.scan(invoice.issued_on.strftime("%d %b %Y")).size).to eq(1)
      expect(response.body).not_to include("View Invoice")
      expect(response.body).to include("View Booking")
      expect(response.body).to include("View Folio")
      expect(response.body).to include(hotel_booking_control_panel_path(hotel, invoice.booking, tab: "booking_details"))
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_control_panel_path(hotel, invoice.booking, tab: "folio_operations", folio_id: invoice.booking_folio_id)))
      payment_link = document.css("a").find { |link| link.text.squish == "Record Received Payment" && link["href"].include?("ar_invoice_id=#{invoice.id}") }
      expect(payment_link["href"]).to eq(new_hotel_ar_payment_path(hotel, ar_invoice_id: invoice.id, hotel_corporate_account_id: invoice.hotel_corporate_account_id))
      expect(document.at_css("table")["class"]).to include("min-w-[1400px]")
      expect(document.css("thead th")).to all(satisfy { |heading| heading["class"].include?("whitespace-nowrap") })
    end

    it "combines search, corporate account, due date, and status filters" do
      relationship = create(:hotel_corporate_account, hotel: hotel, direct_bill_enabled: true)
      matching = create_ar_invoice_for(
        hotel: hotel,
        confirmation_token: "BK-FILTER-MATCH",
        folio_number: 521,
        amount: 210,
        relationship: relationship,
        due_on: Date.current + 5.days
      )
      create_ar_invoice_for(
        hotel: hotel,
        confirmation_token: "BK-FILTER-HIDDEN",
        folio_number: 522,
        amount: 220,
        due_on: Date.current + 8.days
      )

      get hotel_ar_invoices_path(hotel), params: {
        query: "FILTER-MATCH",
        hotel_corporate_account_id: relationship.id,
        due_on: matching.due_on.iso8601,
        status: "open"
      }

      expect(response.body).to include("BK-FILTER-MATCH")
      expect(response.body).not_to include("BK-FILTER-HIDDEN")
    end

    it "renders a resettable empty state when filters have no matches" do
      create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-EMPTY", folio_number: 531, amount: 180)

      get hotel_ar_invoices_path(hotel), params: { query: "does-not-exist" }

      expect(response.body).to include("No AR invoices found")
      expect(response.body).to include("Reset Filters")
    end

    it "ignores invalid account and status filters while preserving hotel scope" do
      create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-SAFE", folio_number: 541, amount: 100)
      create_ar_invoice_for(hotel: other_hotel, confirmation_token: "BK-UNSAFE", folio_number: 542, amount: 100)

      get hotel_ar_invoices_path(hotel), params: {
        hotel_corporate_account_id: "999999",
        status: "invalid",
        due_on: "invalid"
      }

      expect(response.body).to include("BK-SAFE")
      expect(response.body).not_to include("BK-UNSAFE")
    end

    it "requires view reports permission" do
      role.permissions.delete(view_reports)

      get hotel_ar_invoices_path(hotel)

      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
    end
  end

  describe "GET /hotel/:hotel_id/accounts-receivable/aging" do
    it "renders the responsive currency-safe aging report with invoice handoff links" do
      relationship = create(:hotel_corporate_account, hotel: hotel, credit_limit: 100, credit_currency: "MYR", direct_bill_enabled: true)
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-AGING", folio_number: 601, amount: 90, relationship: relationship, due_on: Date.current - 10.days)
      create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-AGING-USD", folio_number: 602, amount: 25, relationship: relationship, due_on: Date.current - 40.days, currency: "USD")
      hidden = create_ar_invoice_for(hotel: other_hotel, confirmation_token: "BK-AGING-HIDDEN", folio_number: 960, amount: 999)

      get hotel_ar_aging_path(hotel)

      document = Nokogiri::HTML(response.body)
      myr_row = document.at_css("[data-testid='aging-row-#{relationship.id}-MYR']")
      usd_row = document.at_css("[data-testid='aging-row-#{relationship.id}-USD']")
      mobile_card = document.at_css("[data-testid='aging-card-#{relationship.id}-MYR']")
      invoices_url = hotel_ar_invoices_path(hotel, hotel_corporate_account_id: relationship.id, balance: "outstanding")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Aging Report")
      expect(response.body).to include("Outstanding corporate balances as of")
      expect(response.body).to include("Current")
      expect(response.body).to include("1–30 days")
      expect(response.body).to include("Total outstanding")
      expect(response.body).to include(invoice.corporate_account.name)
      expect(response.body).to include("MYR 90.00")
      expect(response.body).to include("USD 25.00")
      expect(response.body).to include("Near limit")
      expect(response.body).to include("Not comparable")
      expect(response.body).to include("Credit limit is configured in MYR")
      expect(myr_row["role"]).to eq("link")
      expect(myr_row["tabindex"]).to eq("0")
      expect(myr_row["data-clickable-row-url-value"]).to eq(invoices_url)
      expect(usd_row["data-clickable-row-url-value"]).to eq(invoices_url)
      expect(mobile_card["data-clickable-row-url-value"]).to eq(invoices_url)
      expect(response.body).not_to include(hidden.corporate_account.name)
    end

    it "renders a purposeful empty state when no balances are outstanding" do
      create_ar_invoice_for(
        hotel: hotel,
        confirmation_token: "BK-AGING-PAID",
        folio_number: 603,
        amount: 100,
        outstanding_amount: 0,
        status: "paid"
      )

      get hotel_ar_aging_path(hotel)

      expect(response.body).to include("No outstanding AR balances")
      expect(response.body).to include("Paid, void, and zero-balance invoices do not appear")
    end
  end

  describe "GET /hotel/:hotel_id/accounts-receivable/agent-summary" do
    it "includes only travel_agent and airline accounts, excluding company/government" do
      agent = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent", direct_bill_enabled: true,
        corporate_account: create(:account, :corporate, name: "Sunset Travel Agency"))
      company = create(:hotel_corporate_account, hotel: hotel, account_type: "company", direct_bill_enabled: true,
        corporate_account: create(:account, :corporate, name: "Acme Sdn Bhd"))
      agent_invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-AGENT-SUMMARY", folio_number: 701, amount: 150, relationship: agent, due_on: Date.current - 5.days)
      create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-COMPANY-HIDDEN", folio_number: 702, amount: 500, relationship: company, due_on: Date.current - 5.days)

      get hotel_ar_agent_summary_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Agent Summary Statement")
      expect(response.body).to include(agent_invoice.corporate_account.name)
      expect(response.body).to include("MYR 150.00")
      expect(response.body).not_to include(company.corporate_account.name)
    end

    it "exports a PDF" do
      agent = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent",
        corporate_account: create(:account, :corporate, name: "Sunset Travel Agency"))
      create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-AGENT-PDF", folio_number: 703, amount: 200, relationship: agent, due_on: Date.current - 5.days)

      get hotel_ar_agent_summary_path(hotel, format: :pdf)

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
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
      expect(response.body).to include("Record Received Payment")
    end
  end

  describe "legacy Accounts Receivable paths" do
    it "does not expose old AR invoice and payment paths" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-REDIR", folio_number: 902, amount: 100)

      get "/hotel/#{hotel.slug}/ar-invoices"
      expect(response).to have_http_status(:not_found)

      get "/hotel/#{hotel.slug}/ar-invoices/#{invoice.id}"
      expect(response).to have_http_status(:not_found)

      get "/hotel/#{hotel.slug}/ar-payments/new"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /hotel/:hotel_id/ar-invoices/:id" do
    it "renders source booking, folio, corporate account, due date, and outstanding balance" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-AR-SHOW", folio_number: 701, amount: 450)

      get hotel_ar_invoice_path(hotel, invoice)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(invoice.formatted_invoice_number)
      expect(response.body).to include("BK-AR-SHOW")
      expect(response.body).to include(invoice.booking_folio.folio_reference_display)
      expect(response.body).to include(invoice.corporate_account.name)
      expect(response.body).to include(invoice.due_on.strftime("%d %b %Y"))
      expect(response.body).to include("MYR 450.00")
      expect(response.body).to include("Outstanding")
      expect(response.body).to include("Record Received Payment")
    end

    it "renders the redesigned cards, linked sources, tabs, semantic allocations, and readable snapshots" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-AR-DETAIL", folio_number: 702, amount: 450)
      invoice.hotel_corporate_account.update!(payment_terms_days: 30)
      invoice.update!(
        paid_amount: 125,
        outstanding_amount: 325,
        status: "partially_paid",
        metadata: {
          booking_id: invoice.booking.id,
          payment_terms_days: 30,
          folio_balance: "450.00",
          direct_bill_closed_at: "2026-06-01T00:15:00Z"
        }
      )
      payment = create(
        :ar_payment,
        hotel: hotel,
        hotel_corporate_account: invoice.hotel_corporate_account,
        amount: 125,
        currency: "MYR",
        reference_number: "BANK-SHOW-1",
        received_at: Date.new(2026, 6, 5),
        payment_method: "bank_transfer"
      )
      create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 125)

      get hotel_ar_invoice_path(hotel, invoice)

      document = Nokogiri::HTML(response.body)
      payment_link = document.css("a").find { |link| link.text.squish.include?("Record Received Payment") }
      allocation_row_header = document.at_css("[data-testid='payment-allocations-card'] tbody th[scope='row']")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Accounts Receivable")
      expect(response.body).to include("Invoice Summary")
      expect(response.body).to include("Invoice Details")
      expect(response.body).to include("Original Amount")
      expect(response.body).to include("Paid Amount")
      expect(response.body).to include("Direct Bill Source")
      expect(response.body).to include("Folio close")
      expect(response.body).to include("Net 30 days")
      expect(response.body).to include("Payment Allocations")
      expect(response.body).to include("Technical Snapshots")
      expect(response.body).to include("Payment Terms Days")
      expect(response.body).to include("MYR 450.00")
      expect(response.body).not_to include("<pre")
      expect(document.at_css("a[href='#{hotel_corporate_accounts_path(hotel)}']")).to be_present
      expect(document.at_css("a[href='#{hotel_booking_control_panel_path(hotel, invoice.booking, tab: "booking_details")}']")).to be_present
      expect(document.at_css("a[href='#{hotel_booking_control_panel_path(hotel, invoice.booking, tab: "folio_operations", folio_id: invoice.booking_folio_id)}']")).to be_present
      expect(payment_link["href"]).to eq(new_hotel_ar_payment_path(hotel, ar_invoice_id: invoice.id, hotel_corporate_account_id: invoice.hotel_corporate_account_id))
      expect(allocation_row_header.text.squish).to eq("BANK-SHOW-1")
    end

    it "renders allocation and technical snapshot empty states" do
      invoice = create_ar_invoice_for(hotel: hotel, confirmation_token: "BK-AR-EMPTY", folio_number: 703, amount: 200)

      get hotel_ar_invoice_path(hotel, invoice)

      expect(response.body).to include("No payment allocations yet")
      expect(response.body).to include("No technical snapshot recorded")
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
      expect(response.body).to include(invoice.formatted_invoice_number)
      expect(response.body).to include("allocations[#{invoice.id}]")
      expect(response.body).to include("Reference Number")
      expect(response.body).to include("Received At")
      expect(response.body).to include("Record Received Payment")
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

      expect(response).to redirect_to(hotel_ar_payment_path(hotel, ArPayment.last))
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

  def create_ar_invoice_for(
    hotel:,
    confirmation_token:,
    folio_number:,
    amount:,
    relationship: nil,
    due_on: nil,
    currency: "MYR",
    outstanding_amount: amount,
    status: "open"
  )
    booking = create(:booking, hotel: hotel, confirmation_token: confirmation_token, currency: currency)
    relationship ||= create(:hotel_corporate_account, hotel: hotel, direct_bill_enabled: true)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_number: folio_number, hotel_corporate_account: relationship, currency: currency)
    create(:ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: amount,
      paid_amount: amount.to_d - outstanding_amount.to_d,
      outstanding_amount: outstanding_amount,
      status: status,
      currency: currency,
      due_on: due_on || Date.current + 30.days,
      issued_on: (due_on || Date.current + 30.days) - 30.days)
  end
end
