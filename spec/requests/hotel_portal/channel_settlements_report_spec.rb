# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Hotel portal OTA settlement report", type: :request do
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, plan: plan) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:source) { create(:booking_source, key: "ota_settlement_request", label: "OTA Settlement Request") }

  before do
    permission = Permission.find_by(slug: "view_reports") || create(:permission, name: "View Reports", slug: "view_reports")
    role.permissions << permission
    manage_receipts = Permission.find_by(slug: "manage_ar_payments") || create(:permission, name: "Manage AR Payments", slug: "manage_ar_payments")
    role.permissions << manage_receipts
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    feature = create(:feature, feature_group: feature_group, slug: "excel_pdf_export")
    create(:plan_feature, plan: plan, feature: feature, enabled: true)
    sign_in_as(user)
  end

  it "renders a currency-safe provider reconciliation and report navigation entry" do
    myr_settlement = create_settlement(provider: "booking_com", currency: "MYR", expected: 90, received: 40)
    create_settlement(provider: "agoda", currency: "USD", expected: 75, received: 75)

    get channel_settlements_hotel_reports_path(hotel), params: {
      date_preset: "custom", start_date: "2026-06-01", end_date: "2026-06-30"
    }

    page = Capybara.string(response.body)
    expect(response).to have_http_status(:success)
    expect(page).to have_css("[data-slot='report-page'][data-report='channel-settlements']")
    expect(page).to have_css("h1", exact_text: "OTA settlement report")
    expect(page).to have_css("h2", text: "MYR reconciliation")
    expect(page).to have_css("h2", text: "USD reconciliation")
    expect(page).to have_text(source.label)
    expect(page).to have_text(myr_settlement.channel_manager_reference)
    expect(page).to have_link(myr_settlement.bookings.first.confirmation_token, href: hotel_booking_path(hotel, myr_settlement.bookings.first))
    expect(page).to have_link("Allocate", href: new_hotel_channel_settlement_receipt_path(
      hotel,
      booking_source_id: source.id,
      currency: "MYR",
      allocation_search: myr_settlement.channel_manager_reference
    ))
    expect(page).to have_css("#ota-settlement-status-tabs [data-slot='tabs-trigger']", minimum: 2)
    expect(page).to have_css("[data-slot='tabs-trigger'][aria-current='page']", text: "All")
    expect(page).to have_css("input[type='search'][aria-label='Search OTA settlements']")
    expect(page).to have_text("MYR 90.00")
    expect(page).to have_text("USD 75.00")
    expect(page).to have_link("OTA Settlements", href: channel_settlements_hotel_reports_path(hotel))
    record_receipt = page.find_link("Record receipt")
    expect(record_receipt.find(:xpath, "..")[:class].split).to include("sm:self-end")
    expect(page).to have_link("Export CSV")
    expect(page).to have_link("Export Excel")
    expect(page).to have_no_link("Export PDF")
    expect(page).to have_no_field("payout receipt")
    expect(page).to have_no_button("Retry")
  end

  it "exports the selected range as CSV and XLSX" do
    create_settlement(provider: "channex", currency: "MYR", expected: 120, received: 100)
    params = { start_date: "2026-06-01", end_date: "2026-06-30" }

    get channel_settlements_hotel_reports_path(hotel, format: :csv), params: params
    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("ota-settlements-2026-06-01-2026-06-30.csv")
    csv_rows = CSV.parse(response.body.delete_prefix("﻿"))
    expect(csv_rows.first).to start_with("OTA", "Booking", "Settlement Reference", "Status")
    detail_row = csv_rows.second
    expect(detail_row[0]).to eq(source.label)
    expect(detail_row[1]).to be_present
    expect(detail_row[2]).to eq("channex-MYR")
    expect(detail_row[3]).to include("OTA")
    expect(detail_row[4..]).to eq([ "MYR", "120.00", "100.00", "20.00", "-20.00" ])

    get channel_settlements_hotel_reports_path(hotel, format: :xlsx), params: params
    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    expect(response.headers["Content-Disposition"]).to include("ota-settlements-2026-06-01-2026-06-30.xlsx")
    expect(response.body).to start_with("PK")
  end

  it "applies URL-backed OTA, currency, search, and status filters" do
    included = create_settlement(provider: "channex", currency: "MYR", expected: 90, received: 0)
    included.update!(status: "needs_attention", channel_manager_reference: "visible-settlement")
    create_settlement(provider: "agoda", currency: "USD", expected: 80, received: 0)

    get channel_settlements_hotel_reports_path(hotel), params: {
      q: "visible", source: source.id, currency: "MYR", status: "needs_attention",
      start_date: "2026-06-01", end_date: "2026-06-30"
    }

    page = Capybara.string(response.body)
    expect(response).to have_http_status(:success)
    expect(page).to have_text("visible-settlement")
    expect(page).to have_no_text("agoda-USD")
    expect(page).to have_css("[data-slot='tabs-trigger'][aria-current='page']", text: "Needs attention")
    expect(page).to have_select("source", selected: source.label, visible: :all)
    expect(page).to have_select("currency", selected: "MYR", visible: :all)
  end

  it "paginates settlement details at 25 rows" do
    26.times do |index|
      create_settlement(provider: "ota_provider_#{index}", currency: "MYR", expected: 90, received: 0)
    end

    get channel_settlements_hotel_reports_path(hotel), params: {
      start_date: "2026-06-01", end_date: "2026-06-30"
    }

    page = Capybara.string(response.body)
    detail_table = page.find("caption", text: "OTA settlement details").ancestor("table")
    expect(detail_table).to have_css("tbody tr", count: 25)
    expect(page).to have_css("[data-slot='report-pagination']")
  end

  it "requires view_reports permission" do
    role.permissions.delete(Permission.find_by!(slug: "view_reports"))

    get channel_settlements_hotel_reports_path(hotel)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("You are not authorized to perform this action.")
  end

  private

  def create_settlement(provider:, currency:, expected:, received:)
    settlement = create(
      :channel_settlement,
      hotel: hotel,
      booking_source: source,
      provider: provider,
      currency: currency,
      collection_by: "ota",
      expected_net_amount: expected,
      gross_amount: expected + 10,
      commission_amount: 10,
      channel_manager_reference: "#{provider}-#{currency}",
      created_at: Time.zone.local(2026, 6, 15, 12)
    )
    allocation = create(
      :channel_settlement_allocation,
      channel_settlement: settlement,
      expected_net_amount: expected,
      gross_amount: expected + 10,
      commission_amount: 10
    )
    return settlement if received.zero?

    receipt = create(:channel_settlement_receipt, hotel: hotel, booking_source: source, amount: received, currency: currency)
    create(
      :channel_settlement_receipt_allocation,
      channel_settlement_allocation: allocation,
      channel_settlement_receipt: receipt,
      amount: received,
      currency: currency
    )
    settlement
  end
end
