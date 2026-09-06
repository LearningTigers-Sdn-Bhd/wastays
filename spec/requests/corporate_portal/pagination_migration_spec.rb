# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Corporate portal pagination migration", type: :request do
  let(:user) { create(:user, :corporate) }

  before { sign_in_as(user) }

  it "paginates invoices and preserves all active filters" do
    relationship = create(:hotel_corporate_account, corporate_account: user.account)
    invoices = Array.new(26) { |index| create_invoice(relationship, invoice_number: 80_000 + index) }

    get corporate_ar_invoices_path,
      params: {
        page: 2,
        query: relationship.hotel.name,
        status: "open",
        hotel_id: relationship.hotel_id,
        due_on: (Date.current + 30.days).iso8601,
        balance: "outstanding"
      }

    navigation = pagination_in("corporate_ar_invoices_results")
    previous_url = navigation.at_css('a[aria-label="Previous page"]')["href"]
    expect(response).to have_http_status(:ok)
    expect(navigation.at_css('[aria-current="page"]').text).to eq("2")
    expect(previous_url).to include(
      "query=",
      "status=open",
      "hotel_id=#{relationship.hotel_id}",
      "due_on=#{(Date.current + 30.days).iso8601}",
      "balance=outstanding"
    )
    expect(response.body).to include(invoices.first.formatted_invoice_number)
  end

  it "paginates the merged payment history without hydrating records outside the page" do
    relationship = create(:hotel_corporate_account, corporate_account: user.account)
    payments = Array.new(26) do |index|
      create(
        :ar_payment,
        hotel_corporate_account: relationship,
        hotel: relationship.hotel,
        reference_number: "CORP-PAGE-#{index}",
        received_at: Date.new(2026, 9, 1) + index.days
      )
    end

    get corporate_ar_payments_path, params: { page: 2, query: "CORP-PAGE" }

    navigation = pagination_in("corporate_ar_payments_results")
    expect(response).to have_http_status(:ok)
    expect(navigation.at_css('[aria-current="page"]').text).to eq("2")
    expect(response.body).to include(payments.first.reference_number)
    expect(response.body).not_to include(payments.last.reference_number)
    expect(navigation.at_css('a[aria-label="Previous page"]')["href"]).to include("query=CORP-PAGE")
  end

  it "paginates statement relationships and keeps the search term" do
    relationships = Array.new(26) do |index|
      create(
        :hotel_corporate_account,
        corporate_account: user.account,
        hotel: create(:hotel, name: format("Statement Hotel %02d", index))
      )
    end

    get corporate_ar_statements_path, params: { page: 2, query: "Statement Hotel" }

    navigation = pagination_in("ar_statements_results")
    expect(response).to have_http_status(:ok)
    expect(navigation.at_css('[aria-current="page"]').text).to eq("2")
    expect(response.body).to include(relationships.last.hotel.name)
    expect(navigation.at_css('a[aria-label="Previous page"]')["href"]).to include("query=Statement+Hotel")
  end

  it "materializes only the requested 50-row statement page" do
    relationship = create(:hotel_corporate_account, corporate_account: user.account)
    business_date = Date.new(2026, 9, 30)
    allow_any_instance_of(Hotel).to receive(:current_business_date).and_return(business_date)
    invoices = Array.new(51) do |index|
      create_invoice(
        relationship,
        invoice_number: 90_000 + index,
        issued_on: Date.new(2026, 9, 1),
        created_at: Time.zone.local(2026, 9, 1, 12) + index.seconds
      )
    end

    get corporate_ar_statement_path(relationship),
      params: { page: 2, start_date: "2026-09-01", end_date: "2026-09-30", currency: "MYR" }

    navigation = pagination_in("ar_statement_results")
    expect(response).to have_http_status(:ok)
    expect(navigation.at_css('[aria-current="page"]').text).to eq("2")
    expect(response.body).to include(invoices.last.formatted_invoice_number)
    expect(response.body).not_to include(invoices.first.formatted_invoice_number)
    expect(navigation.at_css('a[aria-label="Previous page"]')["href"]).to include(
      "start_date=2026-09-01",
      "end_date=2026-09-30",
      "currency=MYR"
    )
  end

  private

  def create_invoice(relationship, invoice_number:, issued_on: Date.current, created_at: Time.current)
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: relationship.hotel,
      hotel_corporate_account: relationship
    )
    create(
      :ar_invoice,
      hotel: relationship.hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      invoice_number: invoice_number,
      amount: 100,
      outstanding_amount: 100,
      status: "open",
      issued_on: issued_on,
      due_on: issued_on + 30.days,
      created_at: created_at
    )
  end

  def pagination_in(frame_id)
    Nokogiri::HTML(response.body).at_css("turbo-frame##{frame_id} nav.panel-pagination")
  end
end
