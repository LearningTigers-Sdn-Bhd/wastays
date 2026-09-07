# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel report pagination migration", type: :request do
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, plan: plan) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  before do
    %w[view_reports view_payouts].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.titleize, slug: slug)
      role.permissions << permission
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    %w[arrivals_departures_list booking_source_analysis revenue_allocation_per_night excel_pdf_export].each do |slug|
      feature = create(:feature, feature_group: feature_group, slug: slug)
      create(:plan_feature, plan: plan, feature: feature, enabled: true)
    end

    sign_in_as(user)
  end

  it "keeps the Reports Summary free of dead pagination and exports every daily row" do
    26.times do |index|
      date = Date.new(2026, 5, 1) + index.days
      create(
        :booking,
        hotel: hotel,
        status: "confirmed",
        payment_status: "captured",
        created_at: date.in_time_zone.noon
      )
    end
    params = { date_preset: "custom", start_date: "2026-05-01", end_date: "2026-05-26", page: 2 }

    get hotel_reports_path(hotel), params: params
    expect(Capybara.string(response.body)).to have_no_css("nav.panel-pagination")

    get hotel_reports_path(hotel, format: :csv), params: params
    expect(response.body).to include("2026-05-01", "2026-05-26")
  end

  it "paginates financial breakdowns with stable ordering and complete CSV exports" do
    created_at = Time.zone.local(2026, 5, 6, 12)
    bookings = 26.times.map do |index|
      create(
        :booking,
        hotel: hotel,
        guest_name: "Pagination Guest #{index}",
        status: "confirmed",
        payment_status: "captured",
        created_at: created_at
      )
    end
    params = {
      date_preset: "custom",
      start_date: "2026-05-01",
      end_date: "2026-05-31",
      q: "Pagination Guest"
    }

    get breakdown_hotel_reports_path(hotel), params: params

    page = Capybara.string(response.body)
    pagination = page.find('nav.panel-pagination[aria-label="Report pagination"]')
    page_two = pagination.find('a[aria-label="Page 2"]')
    expect(page).to have_text(bookings.last.confirmation_token)
    expect(page).to have_no_text(bookings.first.confirmation_token)
    expect(page_two[:href]).to include("q=Pagination+Guest", "start_date=2026-05-01", "end_date=2026-05-31")

    get breakdown_hotel_reports_path(hotel), params: params.merge(page: 2)

    page = Capybara.string(response.body)
    expect(page).to have_text(bookings.first.confirmation_token)
    expect(page).to have_no_text(bookings.last.confirmation_token)

    get breakdown_hotel_reports_path(hotel), params: params.merge(page: 99)
    expect(Capybara.string(response.body)).to have_no_css("tbody tr[data-slot='report-date-group']")

    get breakdown_hotel_reports_path(hotel, format: :csv), params: params.merge(page: 2)
    expect(response.body).to include(bookings.first.confirmation_token, bookings.last.confirmation_token)
  end

  it "paginates paid payouts and keeps complete exports inside the payouts frame" do
    batches = 26.times.map do |index|
      create(
        :payout_batch,
        hotel: hotel,
        status: "paid",
        period_start: Date.new(2026, 5, 1),
        period_end: Date.new(2026, 5, 31),
        payout_reference: "PAID-PAGE-#{index}"
      )
    end
    params = { tab: "paid", paid_start_date: "2026-05-01", paid_end_date: "2026-05-31" }

    get payouts_hotel_reports_path(hotel), params: params

    page = Capybara.string(response.body)
    pagination = page.find('turbo-frame#payouts_content nav.panel-pagination[aria-label="Paid payout history pagination"]')
    page_two = pagination.find('a[aria-label="Page 2"]')
    expect(page).to have_text(batches.last.payout_reference)
    expect(page).to have_no_text(batches.first.payout_reference)
    expect(page_two["data-turbo-frame"]).to eq("payouts_content")
    expect(page_two["data-turbo-action"]).to eq("advance")
    expect(page_two[:href]).to include("tab=paid", "paid_start_date=2026-05-01", "paid_end_date=2026-05-31")

    get payouts_hotel_reports_path(hotel), params: params.merge(page: 2)
    expect(response.body).to include(batches.first.payout_reference)
    expect(response.body).not_to include(batches.last.payout_reference)

    get payouts_hotel_reports_path(hotel, format: :csv), params: params.merge(page: 2)
    expect(response.body).to include(batches.first.payout_reference, batches.last.payout_reference)
  end

  it "paginates registration cards inside their Turbo frame with complete counts" do
    check_in = Date.new(2026, 5, 6)
    cards = 26.times.map do |index|
      booking = create(
        :booking,
        hotel: hotel,
        guest_name: "Pagination GRC #{index}",
        check_in: check_in,
        check_out: check_in + 1.day
      )
      create(:guest_registration_card, :signed, hotel: hotel, booking: booking)
    end
    params = {
      tab: "registration_cards",
      start_date: "2026-05-01",
      end_date: "2026-05-31",
      status: "signed",
      q: "Pagination GRC"
    }

    get guest_reports_hotel_reports_path(hotel), params: params

    page = Capybara.string(response.body)
    pagination = page.find('turbo-frame#grc_results nav.panel-pagination[aria-label="Registration card pagination"]')
    page_two = pagination.find('a[aria-label="Page 2"]')
    expect(page).to have_text(cards.last.booking.guest_name)
    expect(page).to have_no_text(cards.first.booking.guest_name)
    expect(page).to have_text("Total cards 26", normalize_ws: true)
    expect(page_two["data-turbo-frame"]).to eq("grc_results")
    expect(page_two["data-turbo-action"]).to eq("advance")
    expect(page_two[:href]).to include("status=signed", "q=Pagination+GRC", "tab=registration_cards")

    get guest_reports_hotel_reports_path(hotel), params: params.merge(page: 2)
    expect(response.body).to include(cards.first.booking.guest_name)
    expect(response.body).not_to include(cards.last.booking.guest_name)

    get guest_reports_hotel_reports_path(hotel), params: params.merge(page: 99)
    expect(Capybara.string(response.body)).to have_text("No guest registration cards found.")
  end

  it "paginates journal batches while metrics and CSV retain the complete range" do
    batches = 26.times.map do |index|
      batch = create(:journal_batch, hotel: hotel, business_date: Date.new(2026, 5, 1) + index.days)
      create(
        :journal_batch_entry,
        journal_batch: batch,
        gl_code: "40#{index.to_s.rjust(2, '0')}",
        description: "Journal page #{index}"
      )
      batch
    end
    params = { start_date: "2026-05-01", end_date: "2026-05-26" }

    get journal_batches_hotel_reports_path(hotel), params: params

    page = Capybara.string(response.body)
    expect(page).to have_text("Journal page 25")
    expect(page).to have_no_text("Journal page 0")
    expect(page).to have_css('nav.panel-pagination a[aria-label="Page 2"]')
    expect(page).to have_text("Journal batches 26", normalize_ws: true)

    get journal_batches_hotel_reports_path(hotel), params: params.merge(page: 2)
    expect(response.body).to include("Journal page 0")
    expect(response.body).not_to include("Journal page 25")

    get journal_batches_hotel_reports_path(hotel, format: :csv), params: params.merge(page: 2)
    expect(response.body).to include("Journal page 0", "Journal page 25")
  end

  it "keeps Daily Revenue and Cashier pagination independent from complete CSV exports" do
    date = Date.new(2026, 5, 6)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    cash_code = hotel.transaction_codes.find_by!(system_key: "cash_payment")

    51.times do |index|
      create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: "adjustment",
        category: "discount",
        amount: -(index + 1),
        description: "Revenue page #{index}",
        posting_date: date
      )
      create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: "payment",
        category: "cash",
        amount: index + 1,
        description: "Cashier page #{index}",
        transaction_code: cash_code,
        posting_date: date
      )
    end
    common_params = { start_date: date.to_s, end_date: date.to_s }

    get daily_report_hotel_reports_path(hotel), params: common_params.merge(tab: "revenue", cashier_page: 2)

    page = Capybara.string(response.body)
    revenue_pagination = page.find('nav.panel-pagination[aria-label="Report pagination"]')
    expect(page).to have_css('[data-testid="charge-register-row"]', count: 50)
    expect(revenue_pagination.find('a[aria-label="Page 2"]')[:href]).to include("cashier_page=2")

    get daily_report_hotel_reports_path(hotel), params: common_params.merge(tab: "revenue", page: 2)
    expect(Capybara.string(response.body)).to have_css('[data-testid="charge-register-row"]', count: 1)

    get daily_report_hotel_reports_path(hotel), params: common_params.merge(tab: "cashier", page: 2)

    page = Capybara.string(response.body)
    cashier_pagination = page.find('nav.panel-pagination[aria-label="Payment activity pagination"]')
    expect(page).to have_css('[data-testid="cashier-row"]', count: 50)
    expect(cashier_pagination.find('a[aria-label="Page 2"]')[:href]).to include("page=2")

    get daily_report_hotel_reports_path(hotel), params: common_params.merge(tab: "cashier", cashier_page: 2)
    expect(Capybara.string(response.body)).to have_css('[data-testid="cashier-row"]', count: 1)

    get daily_report_hotel_reports_path(hotel, format: :csv), params: common_params.merge(tab: "revenue", page: 2)
    expect(response.body).to include("-1.00", "-51.00")

    get daily_report_hotel_reports_path(hotel, format: :csv), params: common_params.merge(tab: "cashier", cashier_page: 2)
    expect(response.body).to include("1.00", "51.00")
  end
end
