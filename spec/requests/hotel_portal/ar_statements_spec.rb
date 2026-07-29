# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe "HotelPortal::ArStatements", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account, name: "AR Manager") }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_reports) { Permission.find_or_create_by!(slug: "view_reports") { |permission| permission.name = "View Reports" } }
  let(:relationship) do
    create(
      :hotel_corporate_account,
      hotel: hotel,
      corporate_account: create(:account, :corporate, name: "Atlas Travel"),
      credit_currency: "MYR",
      payment_terms_days: 30
    )
  end

  before do
    role.permissions << view_reports
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
    allow_any_instance_of(Hotel).to receive(:current_business_date).and_return(Date.new(2026, 6, 30))
  end

  it "lists every linked account with search, balances, unapplied credit, and statement links" do
    create(:user, :corporate, account: relationship.corporate_account, email: "billing@atlas.test")
    invoice = create_invoice(relationship: relationship, amount: 300, issued_on: Date.new(2026, 6, 1))
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 100, received_at: Date.new(2026, 6, 5))
    create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 40)
    empty_relationship = create(:hotel_corporate_account, hotel: hotel, corporate_account: create(:account, :corporate, name: "Empty Corp"))
    hidden = create(:hotel_corporate_account, hotel: other_hotel, corporate_account: create(:account, :corporate, name: "Hidden Corp"))

    get hotel_ar_statements_path(hotel)

    expect(response).to have_http_status(:success)
    # Anchored on the breadcrumb: a bare include("Statements") also matches the
    # sidebar nav and would pass on any page in the portal.
    expect(Nokogiri::HTML(response.body).at_css("#hotel-breadcrumb").text.squish).to include("Accounts Receivable", "Statements")
    expect(response.body).to include("Atlas Travel", "billing@atlas.test", "MYR 200.00", "MYR 60.00")
    expect(response.body).to include("Empty Corp", hotel_ar_statement_path(hotel, empty_relationship))
    expect(response.body).not_to include(hidden.corporate_account.name)

    get hotel_ar_statements_path(hotel), params: { query: "billing@atlas.test" }
    expect(response.body).to include("Atlas Travel")
    expect(response.body).not_to include("Empty Corp")
  end

  it "renders the default month-to-business-date statement and custom currency period" do
    create(:user, :corporate, account: relationship.corporate_account, email: "billing@atlas.test")
    create_invoice(relationship: relationship, amount: 250, issued_on: Date.new(2026, 6, 5), currency: "MYR")
    create_invoice(relationship: relationship, amount: 75, issued_on: Date.new(2026, 6, 8), currency: "USD")

    get hotel_ar_statement_path(hotel, relationship)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Atlas Travel")
    expect(response.body).to include("2026-06-01", "2026-06-30")
    expect(response.body).to include("MYR 250.00")
    expect(response.body).to include("Historical statements are restated using each invoice")

    get hotel_ar_statement_path(hotel, relationship), params: {
      start_date: "2026-06-01",
      end_date: "2026-06-30",
      currency: "USD"
    }

    expect(response.body).to include("USD 75.00")
    expect(response.body).not_to include("MYR 250.00")
  end

  it "always shows the flat ledger on-screen regardless of report_type, and offers per-invoice charge breakdowns only via the Detail PDF download" do
    room_type = create(:room_type, hotel: hotel, name: "Deluxe Room")
    booking = create(:booking, hotel: hotel, confirmation_token: "BK-DETAIL", currency: "MYR", guest_name: "Mr. Detail Guest")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "301")
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship, currency: "MYR")
    invoice = create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: 120, outstanding_amount: 120, currency: "MYR", issued_on: Date.new(2026, 6, 5), due_on: Date.new(2026, 6, 20))
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 120, posting_date: Date.new(2026, 6, 5), description: "Room Charges")

    get hotel_ar_statement_path(hotel, relationship), params: { report_type: "detail" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Statement Activity")
    expect(response.body).not_to include("Invoice Details")
    expect(response.body).not_to include("Report Type")

    get hotel_ar_statement_path(hotel, relationship, format: :pdf), params: { report_type: "detail" }

    expect(response).to have_http_status(:success)
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
    expect(text).to include("ACCOUNT STATEMENT")
    expect(text).not_to include("(DETAIL)")
    expect(text).to include("Mr. Detail Guest")
    expect(text.index("Billing Name")).to be < text.index("STATEMENT SUMMARY")
  end

  it "returns unprocessable content for invalid dates and unavailable currencies" do
    get hotel_ar_statement_path(hotel, relationship), params: {
      start_date: "2026-06-30",
      end_date: "2026-06-01",
      currency: "MYR"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Start date must be on or before end date.")

    get hotel_ar_statement_path(hotel, relationship), params: {
      start_date: "2026-06-01",
      end_date: "2026-07-01",
      currency: "MYR"
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("End date cannot be after the current business date.")

    get hotel_ar_statement_path(hotel, relationship), params: {
      start_date: "2026-06-01",
      end_date: "2026-06-30",
      currency: "USD"
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Currency is not available for this corporate account.")
  end

  it "generates the full PDF without the export feature gate" do
    55.times do |index|
      create_invoice(
        relationship: relationship,
        amount: index + 1,
        issued_on: Date.new(2026, 6, (index % 28) + 1),
        token: "PDF-#{index}"
      )
    end

    get hotel_ar_statement_path(hotel, relationship, format: :pdf), params: {
      start_date: "2026-06-01",
      end_date: "2026-06-30",
      currency: "MYR"
    }

    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to include("inline")
    expect(text).to include("ACCOUNT STATEMENT", "PDF-0", "PDF-54", "Printed at")
  end

  it "paginates HTML activity without changing report totals" do
    55.times do |index|
      create_invoice(
        relationship: relationship,
        amount: 10,
        issued_on: Date.new(2026, 6, (index % 28) + 1),
        token: "PAGE-#{index}"
      )
    end

    get hotel_ar_statement_path(hotel, relationship), params: {
      start_date: "2026-06-01",
      end_date: "2026-06-30",
      currency: "MYR",
      page: 2
    }

    document = Nokogiri::HTML(response.body)
    activity_rows = document.css("#ar_statement_results tbody tr")
    expect(response).to have_http_status(:success)
    expect(activity_rows.size).to eq(5)
    expect(response.body).to include("MYR 550.00")
  end

  it "enforces hotel tenancy and view reports permission" do
    hidden = create(:hotel_corporate_account, hotel: other_hotel)

    get hotel_ar_statement_path(hotel, hidden)
    expect(response).to have_http_status(:not_found)

    role.permissions.delete(view_reports)
    get hotel_ar_statements_path(hotel)
    expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
  end

  def create_invoice(relationship:, amount:, issued_on:, currency: "MYR", token: nil)
    booking = create(:booking, hotel: relationship.hotel, confirmation_token: token || SecureRandom.hex(5), currency: currency)
    folio = create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: relationship.hotel,
      hotel_corporate_account: relationship,
      currency: currency
    )
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
