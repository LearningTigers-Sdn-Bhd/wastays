# frozen_string_literal: true

require 'rails_helper'
require "nokogiri"
require "pdf-reader"
require "zip"

RSpec.describe "HotelPortal::Reports", type: :request do
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, plan: plan, allow_boat_information: false) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  def enable_plan_feature(slug)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: slug), enabled: true)
  end

  # The guest cell also holds a hover popover, so read its name from its own slot.
  def bibo_row_cells(table)
    row = table.css("tbody tr").first
    [ row.at_css("[data-slot='bibo-guest-name']").text.strip ] + row.css("td").map { |cell| cell.text.strip }
  end

  def create_grouped_room_bookings(count:, hotel:, booking_attributes:, room_attributes:)
    group = create(:group_booking, hotel: hotel)

    count.times.map do |index|
      booking = create(:booking, **booking_attributes, hotel: hotel, group_booking: group, group_position: index + 1)
      create(:booking_room, **room_attributes, booking: booking)
      booking
    end
  end

  before do
    [ "view_reports", "view_payouts" ].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.titleize, slug: slug)
      role.permissions << permission
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    %w[
      daily_occupancy_revenue
      arrivals_departures_list
      outstanding_balance_noshow
      housekeeper_productivity
      booking_source_analysis
      revenue_allocation_per_night
      excel_pdf_export
    ].each { |slug| enable_plan_feature(slug) }
    sign_in_as(user)
  end

  it "shows contextual information beside every report heading" do
    {
      guest_reports_hotel_reports_path(hotel) => "Guest reports",
      tax_compliance_hotel_reports_path(hotel) => "Tax & compliance",
      extra_charge_hotel_reports_path(hotel) => "Extra charge report",
      daily_occupancy_hotel_reports_path(hotel) => "Daily occupancy report",
      outstanding_balance_hotel_reports_path(hotel) => "Outstanding balance report",
      deposit_liability_hotel_reports_path(hotel) => "Deposit liability report",
      daily_report_hotel_reports_path(hotel) => "Daily report",
      refund_report_hotel_reports_path(hotel) => "Monthly refund report"
    }.each do |path, title|
      get path

      expect(response).to have_http_status(:success)
      expect(Capybara.string(response.body)).to have_css("button[aria-label='About #{title}']")
    end
  end

  it "presents this year as monthly periods across report pages" do
    travel_to(Time.zone.local(2026, 7, 23, 10, 0, 0)) do
      booking = create(
        :booking,
        hotel: hotel,
        status: "checked_in",
        payment_status: "captured",
        check_in: Date.new(2026, 5, 6),
        check_out: Date.new(2026, 5, 8),
        guest_country: "Japan",
        tourism_tax_amount: 20,
        tourism_tax_collected: true,
        created_at: Time.zone.local(2026, 5, 7, 10, 0, 0)
      )
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100, posting_date: Date.new(2026, 5, 7))
      create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 100, posting_date: Date.new(2026, 5, 7))

      [
        breakdown_hotel_reports_path(hotel),
        guest_reports_hotel_reports_path(hotel, tab: "in_house"),
        tax_compliance_hotel_reports_path(hotel, tab: "tourism_tax"),
        daily_report_hotel_reports_path(hotel, tab: "cashier"),
        daily_report_hotel_reports_path(hotel, tab: "revenue")
      ].each do |path|
        get path, params: { date_preset: "this_year" }

        expect(response).to have_http_status(:success)
        expect(Capybara.string(response.body)).to have_css("[data-slot='report-month-group']", text: "May 2026")
      end
    end
  end

  describe "GET /index" do
    it "presents an overview for every report group" do
      get hotel_reports_path(hotel)

      page = Capybara.string(response.body)
      expect(page).to have_css("h1", exact_text: "Reports summary")
      expect(page).to have_css("[data-slot='reports-summary-group']", count: 4)

      [ "Financial", "Tax & compliance", "Guest operations", "Accounting" ].each do |label|
        expect(page).to have_css("h2", exact_text: label)
      end
      expect(page).to have_no_link("View report")

      expect(page).to have_text("Booking date")
      expect(page).to have_text("Posting date")
      expect(page).to have_text("Stay date")
      expect(page).to have_text("Business date")
    end

    it "does not render duplicate report actions" do
      get hotel_reports_path(hotel)

      page = Capybara.string(response.body)
      expect(page).to have_no_link("View report")
    end

    it "returns http success" do
      get "/hotel/#{hotel.id}/reports"

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css("[data-slot='report-page'][data-report='reports-summary']")
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card", count: 16)
      expect(page).to have_css("[data-slot='reports-summary-group']", count: 4)
      expect(page).to have_css(".panel-page-header__actions", text: "Time period")
      expect(page).to have_no_css("section[aria-label='Reports summary filters']")
      expect(page).to have_no_css(".panel-form-field[data-size='md'] input[type='search']")
      expect(page).to have_no_css("table.panel-table")
    end

    it "uses sentence-case report copy" do
      get hotel_reports_path(hotel), params: {
        date_preset: "custom",
        start_date: "2026-05-01",
        end_date: "2026-05-31"
      }

      page = Capybara.string(response.body)
      expect(page).to have_css("h1", exact_text: "Reports summary")
      expect(page).to have_css("turbo-frame#reports_content .panel-page-header__caption")
      caption = page.find(".panel-page-header__caption")
      expect(caption).to have_text(hotel.name)
      expect(caption).to have_text("01 May 2026 - 31 May 2026")
      expect(page).to have_css("h2", exact_text: "Financial")
      expect(page).to have_css("h2", exact_text: "Tax & compliance")
      expect(page).to have_css("h2", exact_text: "Guest operations")
      expect(page).to have_css("h2", exact_text: "Accounting")
      expect(page).to have_field("Time period", visible: :all)
      expect(page).to have_no_field("Time Period", visible: :all)
      expect(response.body).to include("Date range")
      expect(response.body).not_to include("Date Range")
    end

    it "keeps the financial summary free of a detailed ledger" do
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", total_amount: 300, margin_amount: 30, net_amount: 270, created_at: Time.zone.local(2026, 5, 6, 12, 0))

      get hotel_reports_path(hotel), params: { date_preset: "custom", start_date: "2026-05-01", end_date: "2026-05-31" }

      page = Capybara.string(response.body)
      expect(page).to have_no_link("View report")
      expect(page).to have_no_css("[data-slot='daily-ledger-trigger']")
    end

    it "exports financial performance csv/xlsx/pdf" do
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", total_amount: 300, margin_amount: 30, net_amount: 270, created_at: Time.zone.local(2026, 5, 6, 12, 0))

      get "/hotel/#{hotel.id}/reports.csv"
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")

      get "/hotel/#{hotel.id}/reports.xlsx"
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")

      get "/hotel/#{hotel.id}/reports.pdf"
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
    end

    it "does not offer a financial-only export from the cross-report summary" do
      get hotel_reports_path(hotel), params: { start_date: "2026-05-06", end_date: "2026-05-08" }

      expect(response.body).not_to include("Export Excel")
      expect(response.body).not_to include("Export CSV")
    end

    it "parses date_range without rendering detailed report actions" do
      get hotel_reports_path(hotel), params: { date_range: "2026-05-06/2026-05-08", q: "A&B" }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css('select[name="date_preset"] option[selected][value="custom"]')
      expect(page).to have_css('input[name="date_range"][value="2026-05-06/2026-05-08"]', visible: :all)
      expect(page).to have_no_link("View report")
    end

    it "prefers resolved dates over a relative preset" do
      get hotel_reports_path(hotel), params: {
        date_preset: "today",
        start_date: "2026-05-06",
        end_date: "2026-05-08"
      }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css(".panel-page-header__caption", text: "06 May 2026 - 08 May 2026")
      expect(page).to have_no_link("View report")
    end
  end

  describe "GET /guest_reports" do
    let(:start_date) { Date.new(2026, 5, 7) }
    let(:end_date) { Date.new(2026, 5, 8) }

    it "renders compact guest reports anatomy for every active tab" do
      hotel.update!(allow_boat_information: true)

      {
        "arrivals" => { tables: 1, metrics: 4 },
        "in_house" => { tables: 1, metrics: 4 },
        "departures" => { tables: 1, metrics: 4 },
        "checkout" => { tables: 1, metrics: 4 },
        "registration_cards" => { tables: 1, metrics: 3 },
        "bibo" => { tables: 2, metrics: 0 },
        "meal_prep" => { tables: 1, metrics: 0 }
      }.each do |tab, expected|
        get guest_reports_hotel_reports_path(hotel), params: {
          start_date: start_date.to_s,
          end_date: end_date.to_s,
          tab: tab
        }

        page = Capybara.string(response.body)
        expect(response).to have_http_status(:success)
        expect(page).to have_css("[data-slot='report-page'][data-report='guest-reports']")
        expect(page).to have_css("#guest-reports-tabs.tabs-root--line")
        expect(page).to have_css(
          "table.panel-table[data-density='compact'][data-header-style='sentence']",
          count: expected[:tables]
        )
        expect(page).to have_css(
          "[data-slot='report-metric-strip'] .panel-metric-card",
          count: expected[:metrics]
        )
        if tab == "registration_cards"
          expect(page).to have_css(
            "[data-slot='report-metric-strip'] ~ section[aria-label='Registration card filters']"
          )
        end
      end
    end

    it "shows the boat column on every arrivals-style tab, checkout included" do
      hotel.update!(allow_boat_information: true)

      { "arrivals" => "Boat arrival", "in_house" => "Boat departure",
        "departures" => "Boat departure", "checkout" => "Boat departure" }.each do |tab, heading|
        get guest_reports_hotel_reports_path(hotel), params: {
          start_date: start_date.to_s, end_date: end_date.to_s, tab: tab
        }

        headings = Nokogiri::HTML(response.body).css("table thead th").map(&:text).map(&:strip)
        expect(headings).to include(heading), "expected a #{heading} column on #{tab}"
      end
    end

    it "shows each boat leg on screen with the same columns its export carries" do
      hotel.update!(allow_boat_information: true, time_zone: "UTC")
      booking = create(:booking, hotel: hotel, check_in: start_date, check_out: end_date)
      create(:booking_room, booking: booking, room_number: "103")
      create(
        :booking_guest,
        booking: booking, guest: create(:guest, name: "Boat Guest"), is_primary: true,
        boat_in_at: start_date.beginning_of_day + 7.hours, boat_out_at: end_date.beginning_of_day + 13.hours
      )

      get guest_reports_hotel_reports_path(hotel), params: {
        start_date: start_date.to_s, end_date: end_date.to_s, tab: "bibo"
      }

      tables = Nokogiri::HTML(response.body).css("table.panel-table")
      expect(tables.map { |table| table.css("thead th").map { |th| th.text.strip } }).to eq([
        [ "Guest name", "Room number", "Arrival Date", "Arrival Time" ],
        [ "Guest name", "Room number", "Departure Date", "Departure Time" ]
      ])
      expect(bibo_row_cells(tables.first)).to eq([ "Boat Guest", "103", start_date.strftime("%d %b %Y"), "07:00 AM" ])
      expect(bibo_row_cells(tables.last)).to eq([ "Boat Guest", "103", end_date.strftime("%d %b %Y"), "01:00 PM" ])
    end

    it "keeps the booking a guest belongs to behind a hover popover, not in a column" do
      hotel.update!(allow_boat_information: true, time_zone: "UTC")
      booking = create(:booking, hotel: hotel, check_in: start_date, check_out: end_date)
      create(:booking_room, booking: booking, room_number: "103")
      create(
        :booking_guest,
        booking: booking, guest: create(:guest, name: "Boat Guest"), is_primary: true,
        boat_in_at: start_date.beginning_of_day + 7.hours
      )

      get guest_reports_hotel_reports_path(hotel), params: {
        start_date: start_date.to_s, end_date: end_date.to_s, tab: "bibo"
      }

      page = Capybara.string(response.body)
      trigger = page.find("[aria-label='Booking details for Boat Guest']", visible: :all)
      panel = page.find("##{trigger['aria-controls']}", visible: :all)

      expect(panel).to have_text(booking.confirmation_token)
      expect(panel).to have_text("Stay dates")
      # The time column is plain text now, no badge.
      expect(page.first("table.panel-table tbody td:last-child", visible: :all)).to have_no_css(".panel-badge")
    end

    it "builds the meal prep report once per page load, not once per badge" do
      hotel.update!(allow_boat_information: true)
      allow(HotelPortal::Reports::MealPrepReport).to receive(:new).and_call_original

      get guest_reports_hotel_reports_path(hotel), params: {
        start_date: start_date.to_s, end_date: end_date.to_s, tab: "meal_prep"
      }

      expect(response).to have_http_status(:success)
      expect(HotelPortal::Reports::MealPrepReport).to have_received(:new).once
    end

    it "keeps the checkout CSV export in step with its on-screen boat column" do
      hotel.update!(allow_boat_information: true)

      get guest_reports_hotel_reports_path(hotel, format: :csv), params: {
        start_date: start_date.to_s, end_date: end_date.to_s, tab: "checkout"
      }

      expect(response.body.lines.first).to include("Boat-out")
    end

    it "keeps guest table screen widths but removes table and wrapper constraints for print" do
      hotel.update!(allow_boat_information: true)
      screen_widths = {
        "arrivals" => "min-w-[960px]",
        "registration_cards" => "min-w-[880px]",
        "bibo" => "min-w-[720px]",
        "meal_prep" => "min-w-[760px]"
      }

      screen_widths.each do |tab, screen_width|
        get guest_reports_hotel_reports_path(hotel), params: {
          start_date: start_date.to_s,
          end_date: end_date.to_s,
          tab: tab
        }

        page = Capybara.string(response.body)
        page.all("table.panel-table").each do |table|
          expect(table[:class].split).to include(screen_width, "print:min-w-0", "print:w-auto")
          expect(table.find(:xpath, "..")[:class].split).to include("print:overflow-visible")
        end
      end
    end

    it "renders the guest reports page for the selected date range" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Arriving Guest", confirmation_token: "WS-ARR")
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: start_date, guest_name: "Departing Guest", confirmation_token: "WS-DEP")
      create(:booking, hotel: hotel, status: "confirmed", check_in: end_date + 1.day, check_out: end_date + 2.days, guest_name: "Wrong Date")

      get guest_reports_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Guest reports")
      expect(response.body).to include("Expected arrivals")
      expect(response.body).to include("Arriving Guest")
      expect(response.body).not_to include("Wrong Date")
    end

    it "renders and exports the police report from guest reports" do
      booking = create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Police Guest", confirmation_token: "POLICE-123")
      guest = create(:guest, name: "Police Guest", country: "Malaysia", document_type: "ic", government_id: "900101135555")
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      get guest_reports_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s, tab: "police_report" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Police report records", "Police Guest", "POLICE-123", "Nights stayed")
      expect(Capybara.string(response.body)).to have_no_css("[data-slot='report-metric-strip']")
      expect(Capybara.string(response.body)).to have_css("th", text: "Nights stayed")
      expect(Capybara.string(response.body)).to have_css("th", text: "Guest")
      expect(Capybara.string(response.body)).to have_css("th", text: "Guest details")
      expect(Capybara.string(response.body)).to have_css("th", text: "Contact")
      expect(Capybara.string(response.body)).to have_css("th", text: "Scheduled check-in")

      get guest_reports_hotel_reports_path(hotel, format: :pdf), params: { start_date: start_date.to_s, end_date: end_date.to_s, tab: "police_report" }

      expect(response.content_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
    end

    it "separates police report rows by month for This Year" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 10), check_out: Date.new(2026, 5, 12), guest_name: "May police guest")
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 6, 10), check_out: Date.new(2026, 6, 12), guest_name: "June police guest")

      get guest_reports_hotel_reports_path(hotel), params: { date_preset: "this_year", start_date: "2026-01-01", end_date: "2026-12-31", tab: "police_report" }

      page = Capybara.string(response.body)
      expect(page).to have_css("[data-slot='report-month-group']", text: "May 2026")
      expect(page).to have_css("[data-slot='report-month-group']", text: "June 2026")
    end

    it "uses the approved empty state for police report periods without stays" do
      get guest_reports_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s, tab: "police_report" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No guest stays in this selected period.")
    end

    it "redirects the legacy arrivals_departures URL to guest reports" do
      get arrivals_departures_hotel_reports_path(hotel), params: { tab: "registration_cards" }

      expect(response).to redirect_to(guest_reports_hotel_reports_path(hotel, tab: "registration_cards"))
    end

    it "renders guest reports heading and defaults invalid tab to arrivals" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Arriving Guest")
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: start_date + 1.day, guest_name: "In House Guest")

      get guest_reports_hotel_reports_path(hotel), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s,
        tab: "bad-tab"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Guest reports")
      expect(response.body).to include("Expected arrivals")
      expect(response.body).to include("Arriving Guest")
    end

    it "renders in-house tab content when tab=in_house" do
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "In House Guest")
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: end_date, guest_name: "Arrival Guest")

      get guest_reports_hotel_reports_path(hotel), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s,
        tab: "in_house"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Guest reports")
      expect(response.body).to include("In-house guests")
      expect(response.body).to include("In House Guest")
    end

    it "renders the registration cards tab from guest reports with date filtering and no export menu" do
      matching_booking = create(:booking, hotel: hotel, guest_name: "Current GRC", check_in: start_date, check_out: start_date + 1.day)
      old_booking = create(:booking, hotel: hotel, guest_name: "Old GRC", check_in: start_date - 1.month, check_out: start_date - 1.month + 1.day)
      create(:guest_registration_card, :signed, booking: matching_booking, hotel: hotel)
      create(:guest_registration_card, booking: old_booking, hotel: hotel)

      get guest_reports_hotel_reports_path(hotel), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s,
        tab: "registration_cards"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Registration cards")
      expect(response.body).to include("Current GRC")
      expect(response.body).not_to include("Old GRC")
      expect(response.body).to include(hotel_booking_guest_registration_card_path(hotel, matching_booking))
      expect(response.body).not_to include("Export PDF")
      expect(response.body).not_to include("Export Excel")
      expect(response.body).not_to include("Export CSV")
      expect(Capybara.string(response.body)).to have_css(".panel-select-menu select.panel-select-menu__native[name='status']", visible: :all)
      expect(Capybara.string(response.body)).to have_no_css("select[name='status']:not(.panel-select-menu__native)", visible: :all)
    end

    it "filters and searches registration cards from guest reports" do
      signed_booking = create(:booking, hotel: hotel, guest_name: "Jane GRC", confirmation_token: "GRC-JANE", check_in: start_date, check_out: start_date + 1.day)
      draft_booking = create(:booking, hotel: hotel, guest_name: "Ali Draft", confirmation_token: "GRC-ALI", check_in: start_date, check_out: start_date + 1.day)
      create(:guest_registration_card, :signed, booking: signed_booking, hotel: hotel)
      create(:guest_registration_card, booking: draft_booking, hotel: hotel)

      get guest_reports_hotel_reports_path(hotel), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s,
        tab: "registration_cards",
        status: "signed",
        q: "Jane"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Jane GRC")
      expect(response.body).not_to include("Ali Draft")
      expect(response.body).to include("data-controller=\"auto-submit\"")
      expect(response.body).to include("data-turbo-frame=\"grc_results\"")
    end

    it "does not export registration cards from guest reports" do
      get guest_reports_hotel_reports_path(hotel, format: :csv), params: { tab: "registration_cards" }

      expect(response).to have_http_status(:not_acceptable)
    end

    it "keeps today selected when switching guest report tabs" do
      travel_to(Time.zone.local(2026, 6, 15, 10, 0, 0)) do
        create(:booking, hotel: hotel, status: "checked_in", check_in: Date.new(2026, 6, 14), check_out: Date.new(2026, 6, 16), guest_name: "In House Guest")

        get guest_reports_hotel_reports_path(hotel), params: { tab: "in_house" }
        doc = Nokogiri::HTML(response.body)
        selected = doc.at_css('select[name="date_preset"] option[selected]')

        expect(response).to have_http_status(:success)
        expect(selected["value"]).to eq("today")
        expect(response.body).to include("In-house guests")
      end
    end

    it "does not show bookings from another hotel" do
      create(:booking, hotel: create(:hotel), status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Other Hotel Guest")

      get guest_reports_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Other Hotel Guest")
    end

    it "defaults guest reports first load to today" do
      travel_to(Time.zone.local(2026, 6, 15, 10, 0, 0)) do
        create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 6, 15), check_out: Date.new(2026, 6, 16), guest_name: "Today Arrival")
        create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 6, 1), check_out: Date.new(2026, 6, 2), guest_name: "Earlier Month Arrival")

        get guest_reports_hotel_reports_path(hotel)
        doc = Nokogiri::HTML(response.body)
        selected = doc.at_css('select[name="date_preset"] option[selected]')

        expect(response).to have_http_status(:success)
        expect(response.body).to include("15 Jun")
        expect(selected["value"]).to eq("today")
      end
    end

    it "falls back to today when both start and end dates are invalid" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current, check_out: Date.current + 1.day, guest_name: "Today Guest")

      get guest_reports_hotel_reports_path(hotel), params: { start_date: "bad-start", end_date: "bad-end" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(Date.current.strftime("%d %b"))
    end

    it "supports single-date legacy param for backward compatibility" do
      date = Date.new(2026, 5, 10)
      create(:booking, hotel: hotel, status: "confirmed", check_in: date, check_out: date + 1.day, guest_name: "Legacy Date Guest")

      get guest_reports_hotel_reports_path(hotel), params: { date: date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("10 May")
    end

    it "aligns end date to start date when start date is later than end date" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 10), check_out: Date.new(2026, 5, 11), guest_name: "Start Date Guest")
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 8), check_out: Date.new(2026, 5, 9), guest_name: "Old Date Guest")

      get guest_reports_hotel_reports_path(hotel), params: {
        start_date: "2026-05-10",
        end_date: "2026-05-09"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("10 May")
      expect(response.body).not_to include("08 May")
    end

    it "normalizes a reversed date_range and preserves the active tab in export links" do
      get guest_reports_hotel_reports_path(hotel), params: {
        date_range: "2026-05-10/2026-05-08",
        tab: "departures"
      }

      page = Capybara.string(response.body)
      expected_href = guest_reports_hotel_reports_path(
        hotel,
        start_date: "2026-05-10",
        end_date: "2026-05-10",
        date_preset: "custom",
        tab: "departures",
        q: nil,
        format: :csv
      )

      expect(response).to have_http_status(:success)
      expect(page).to have_css('input[name="date_range"][value="2026-05-10/2026-05-10"]', visible: :all)
      expect(page).to have_link("Export CSV", href: expected_href)
      expect(page.find_link("Export CSV")["data-turbo"]).to eq("false")
    end

    it "exports CSV for the selected range" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "CSV Guest", confirmation_token: "WS-CSV")

      get guest_reports_hotel_reports_path(hotel, format: :csv), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Section,Guest Name,Booking Ref,Rooms,Room Numbers,Stay,Pre-checkin Status,Guarantee Method,Deposit Status,Departure Status,Notes")
      expect(response.body).to include("CSV Guest")
      expect(response.body).to include("WS-CSV")
    end

    it "exports CSV for the active checkout tab only" do
      create(:booking, hotel: hotel, status: "completed", check_in: start_date - 1.day, check_out: start_date, guest_name: "Checked Out Guest", confirmation_token: "WS-CHECKOUT")
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: start_date, guest_name: "Due Out Guest", confirmation_token: "WS-DUEOUT")

      get guest_reports_hotel_reports_path(hotel, format: :csv), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s,
        tab: "checkout"
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.headers["Content-Disposition"]).to include("guest-reports-checkout")
      expect(response.body).to include("Checked Out Guest")
      expect(response.body).not_to include("Due Out Guest")
    end

    it "exports PDF for the selected range" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "PDF Guest", confirmation_token: "WS-PDF")

      get guest_reports_hotel_reports_path(hotel, format: :pdf), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include(".pdf")
    end

    it "exports Excel for the default arrivals tab" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Excel Guest", confirmation_token: "WS-XLS")

      get guest_reports_hotel_reports_path(hotel, format: :xlsx), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.headers["Content-Disposition"]).to include(".xlsx")
      expect(response.body).to start_with("PK")
    end
  end

  describe "GET /non_national" do
    it "redirects to tax_compliance with tab=non_national (merged into that report)" do
      get non_national_hotel_reports_path(hotel), params: { start_date: "2026-07-01", end_date: "2026-07-01" }

      expect(response).to redirect_to("/hotel/#{hotel.to_param}/reports/tax_compliance?tab=non_national&start_date=2026-07-01&end_date=2026-07-01")
    end

    it "preserves csv format and ignores an incoming tab override" do
      get non_national_hotel_reports_path(hotel, format: :csv), params: { tab: "sst", start_date: "2026-07-01" }

      expect(response).to redirect_to("/hotel/#{hotel.to_param}/reports/tax_compliance.csv?tab=non_national&start_date=2026-07-01")
    end
  end

  describe "GET /tourism_tax" do
    it "redirects to tax_compliance with tab=tourism_tax (merged into that report)" do
      get tourism_tax_hotel_reports_path(hotel), params: { start_date: "2026-07-01", end_date: "2026-07-01" }

      expect(response).to redirect_to("/hotel/#{hotel.to_param}/reports/tax_compliance?tab=tourism_tax&start_date=2026-07-01&end_date=2026-07-01")
    end
  end

  describe "GET /sst" do
    it "redirects to tax_compliance with tab=sst (merged into that report)" do
      get sst_hotel_reports_path(hotel), params: { start_date: "2026-07-01", end_date: "2026-07-01" }

      expect(response).to redirect_to("/hotel/#{hotel.to_param}/reports/tax_compliance?tab=sst&start_date=2026-07-01&end_date=2026-07-01")
    end

    it "preserves pdf format" do
      get sst_hotel_reports_path(hotel, format: :pdf), params: { start_date: "2026-07-01" }

      expect(response).to redirect_to("/hotel/#{hotel.to_param}/reports/tax_compliance.pdf?tab=sst&start_date=2026-07-01")
    end
  end

  describe "GET /tax_compliance" do
    let(:start_date) { Date.new(2026, 7, 1) }
    let(:end_date) { Date.new(2026, 7, 1) }

    it "renders compact report anatomy for every tax compliance tab" do
      {
        "tourism_tax" => 3,
        "sst" => 4,
        "non_national" => 2
      }.each do |tab, metric_count|
        get tax_compliance_hotel_reports_path(hotel), params: {
          tab: tab,
          start_date: start_date.to_s,
          end_date: end_date.to_s
        }

        page = Capybara.string(response.body)
        expect(response).to have_http_status(:success)
        expect(page).to have_css("[data-slot='report-page'][data-report='tax-compliance']")
        expect(page).to have_css("#tax-compliance-tabs.tabs-root--line")
        expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card", count: metric_count)
        expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']")
      end
    end

    it "defaults to the tourism_tax tab and renders it" do
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Kenji Sato", guest_country: "Japan", tourism_tax_amount: 20, tourism_tax_collected: true)

      get tax_compliance_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(Capybara.string(response.body)).to have_text("Tax & compliance")
      expect(response.body).to include("Kenji Sato")
      expect(response.body).to include("MYR 20.00")
    end

    it "renders the sst tab" do
      booking = create(:booking, hotel: hotel, guest_name: "Amira Yusof")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "tax", description: "Service Tax (SST 8%)", posting_date: start_date, amount: 16)

      get tax_compliance_hotel_reports_path(hotel), params: { tab: "sst", start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Amira Yusof")
    end

    it "renders the non_national tab" do
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Overseas Guest", guest_country: "Japan")

      get tax_compliance_hotel_reports_path(hotel), params: { tab: "non_national", start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Overseas Guest")
    end

    it "falls back to tourism_tax for an unknown tab" do
      get tax_compliance_hotel_reports_path(hotel), params: { tab: "bogus", start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      page = Capybara.string(response.body)
      expect(page).to have_css('[data-testid="tax-compliance-tab-tourism-tax"][aria-current="page"]')
    end

    it "exports csv for the active tab" do
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "CSV Foreigner", guest_country: "Singapore", tourism_tax_amount: 10, tourism_tax_collected: false, confirmation_token: "WS-CSV-TTX")

      get tax_compliance_hotel_reports_path(hotel, format: :csv), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.headers["Content-Disposition"]).to include("tax-compliance-tourism-tax")
      expect(response.body).to include("CSV Foreigner")
    end

    it "exports xlsx for the active tab" do
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Excel Foreigner", guest_country: "Japan", tourism_tax_amount: 15, tourism_tax_collected: true)

      get tax_compliance_hotel_reports_path(hotel, format: :xlsx), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.headers["Content-Disposition"]).to include("tax-compliance-tourism-tax")
      expect(response.headers["Content-Disposition"]).to include(".xlsx")
    end

    it "exports pdf for the active tab" do
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "PDF Foreigner", guest_country: "Japan", tourism_tax_amount: 15, tourism_tax_collected: true)

      get tax_compliance_hotel_reports_path(hotel, format: :pdf), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
    end
  end

  describe "GET /extra_charge" do
    def create_extra_charge_export_rows
      booking = create(:booking, hotel: hotel, guest_name: "Export Guest")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "fb", description: "F&B export charge", amount: 20, posting_date: Date.new(2026, 6, 15))
      create(:folio_transaction, booking_folio: folio, category: "other", description: "Non-F&B export charge", amount: 15, posting_date: Date.new(2026, 6, 15))
    end

    def xlsx_text(content)
      entries = {}
      Zip::File.open_buffer(StringIO.new(content)) do |archive|
        archive.each { |entry| entries[entry.name] = entry.get_input_stream.read }
      end

      shared_strings = if (content = entries["xl/sharedStrings.xml"])
        Nokogiri::XML(content).xpath("//xmlns:si").map { |string| string.xpath(".//xmlns:t").map(&:text).join }
      else
        []
      end

      entries.filter_map do |name, worksheet|
        next unless name.match?(%r{\Axl/worksheets/.+\.xml\z})

        document = Nokogiri::XML(worksheet)
        document.xpath("//xmlns:c").filter_map do |cell|
          inline_text = cell.xpath("./xmlns:is//xmlns:t").map(&:text).join
          next inline_text if inline_text.present?
          next shared_strings.fetch(cell.at_xpath("./xmlns:v")&.text.to_i) if cell["t"] == "s"

          cell.at_xpath("./xmlns:v")&.text
        end.join("\n")
      end.join("\n")
    end

    def pdf_text(content)
      PDF::Reader.new(StringIO.new(content)).pages.map(&:text).join("\n")
    end

    it "renders the extra charge report page" do
      booking = create(:booking, hotel: hotel, guest_name: "FB Guest")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "fb", description: "Restaurant", amount: 20, posting_date: Date.new(2026, 6, 15))

      get extra_charge_hotel_reports_path(hotel), params: {
        start_date: "2026-06-15",
        end_date: "2026-06-15"
      }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css("[data-slot='report-page'][data-report='extra-charge']")
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card", count: 2)
      expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']")
      expect(page).to have_css("h1", exact_text: "Extra charge report")
      expect(page).to have_text("FB Guest")
      expect(page).to have_text("Restaurant")
      expect(page).to have_text("MYR 20.00")
    end

    it "links to xlsx and not xls exports" do
      get extra_charge_hotel_reports_path(hotel), params: {
        tab: "fb",
        start_date: "2026-06-15",
        end_date: "2026-06-15"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(".xlsx")
      expect(response.body).not_to match(/\.xls(?:\?|\"|')/)
    end

    it "defaults to today on first load" do
      travel_to(Time.zone.local(2026, 6, 15, 10, 0, 0)) do
        booking = create(:booking, hotel: hotel, guest_name: "Today FB Guest")
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        create(:folio_transaction, booking_folio: folio, category: "fb", description: "Today Charge", amount: 20, posting_date: Date.new(2026, 6, 15))
        create(:folio_transaction, booking_folio: folio, category: "fb", description: "Earlier Charge", amount: 20, posting_date: Date.new(2026, 6, 1))

        get extra_charge_hotel_reports_path(hotel)
        doc = Nokogiri::HTML(response.body)
        selected = doc.at_css('select[name="date_preset"] option[selected]')

        expect(response).to have_http_status(:success)
        expect(response.body).to include("15 Jun")
        expect(selected["value"]).to eq("today")
      end
    end

    it "shows only non-fb extra charges on the non-fb tab" do
      booking = create(:booking, hotel: hotel, guest_name: "Extra Guest")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "fb", description: "Restaurant", amount: 25, posting_date: Date.new(2026, 6, 15))
      create(:folio_transaction, booking_folio: folio, category: "other", description: "Laundry", amount: 15, posting_date: Date.new(2026, 6, 15))

      get extra_charge_hotel_reports_path(hotel), params: {
        tab: "non_fb",
        start_date: "2026-06-15",
        end_date: "2026-06-15"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Non-F&amp;B")
      expect(response.body).to include("Laundry")
      expect(response.body).not_to include("Restaurant")
      expect(response.body).to include("MYR 15.00")
    end

    it "shows a monthly breakdown when this year is selected" do
      travel_to(Time.zone.local(2026, 7, 22, 10, 0, 0)) do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        create(:folio_transaction, booking_folio: folio, category: "fb", amount: 40, posting_date: Date.new(2026, 5, 7))

        get extra_charge_hotel_reports_path(hotel), params: { date_preset: "this_year" }

        page = Capybara.string(response.body)
        expect(response).to have_http_status(:success)
        expect(page).to have_text("Monthly breakdown")
        expect(page).to have_text("May 2026")
        expect(page).to have_text("MYR 40.00")
        expect(page.all("table.panel-table").map { |table| table.find("caption", visible: :all).text }).to eq([
          "Monthly breakdown",
          "Charge details"
        ])
      end
    end

    it "exports csv for the active tab only" do
      create_extra_charge_export_rows

      get extra_charge_hotel_reports_path(hotel, format: :csv), params: {
        tab: "fb",
        start_date: "2026-06-15",
        end_date: "2026-06-15"
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("extra-charge-report-fb-2026-06-15-2026-06-15.csv")
      expect(response.body).to include("F&B export charge")
      expect(response.body).not_to include("Non-F&B export charge")
    end

    it "exports xlsx for the active tab only" do
      create_extra_charge_export_rows

      get extra_charge_hotel_reports_path(hotel, format: :xlsx), params: {
        tab: "fb",
        start_date: "2026-06-15",
        end_date: "2026-06-15"
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.headers["Content-Disposition"]).to include("extra-charge-report-fb-2026-06-15-2026-06-15.xlsx")
      expect(response.body).to start_with("PK")
      expect(xlsx_text(response.body)).to include("F&B export charge")
      expect(xlsx_text(response.body)).not_to include("Non-F&B export charge")
    end

    it "exports pdf for the active tab only" do
      create_extra_charge_export_rows

      get extra_charge_hotel_reports_path(hotel, format: :pdf), params: {
        tab: "fb",
        start_date: "2026-06-15",
        end_date: "2026-06-15"
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("extra-charge-report-fb-2026-06-15-2026-06-15.pdf")
      expect(pdf_text(response.body)).to include("F&B export charge")
      expect(pdf_text(response.body)).not_to include("Non-F&B export charge")
    end
  end

  describe "GET /daily_occupancy" do
    let(:start_date) { Date.new(2026, 5, 6) }
    let(:end_date) { Date.new(2026, 5, 7) }

    it "renders daily occupancy report for selected range" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      create(:room_inventory, room_type: room_type, date: start_date, quantity: 8, status: "open")
      create(:room_inventory, room_type: room_type, date: end_date, quantity: 9, status: "open")
      create_grouped_room_bookings(
        count: 2,
        hotel: hotel,
        booking_attributes: { status: "confirmed", check_in: start_date, check_out: end_date + 1.day, guest_name: "Occ Guest" },
        room_attributes: { room_type: room_type, subtotal: 150.0 }
      )

      get daily_occupancy_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css("[data-slot='report-page'][data-report='daily-occupancy']")
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card", count: 7)
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card__detail", count: 7)
      expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']")
      expect(page).to have_css("h1", exact_text: "Daily occupancy report")
      expect(page).to have_text("Rooms sold")
    end

    it "renders the two-month date_range component for a custom preset" do
      get daily_occupancy_hotel_reports_path(hotel), params: { date_range: "2026-05-06/2026-05-07" }

      page = Capybara.string(response.body)
      picker = page.find('[data-panels-ui--date-picker-mode-value="range"]')
      expect(response).to have_http_status(:success)
      expect(picker["data-panels-ui--date-picker-months-value"]).to eq("2")
      expect(picker["data-panels-ui--date-picker-responsive-months-value"]).to eq("true")
      expect(picker["data-action"]).to include("change->date-preset#submitDate")
      expect(page).to have_no_button("Apply")
      expect(page).to have_css('[data-controller~="panels-ui--dropdown-menu"]')
      expect(page).to have_no_css("details")
    end

    it "prefers resolved export dates over a relative preset" do
      get daily_occupancy_hotel_reports_path(hotel), params: {
        date_preset: "today",
        start_date: "2026-05-06",
        end_date: "2026-05-08"
      }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_link(
        "Export CSV",
        href: daily_occupancy_hotel_reports_path(
          hotel,
          start_date: "2026-05-06",
          end_date: "2026-05-08",
          date_preset: "today",
          format: :csv
        )
      )
    end

    it "rejects non-ISO date_range endpoints" do
      travel_to(Time.zone.local(2026, 6, 15, 10, 0, 0)) do
        get daily_occupancy_hotel_reports_path(hotel), params: { date_range: "2026-05-06junk/2026-05-08" }

        page = Capybara.string(response.body)
        expect(response).to have_http_status(:success)
        expect(page).to have_css('input[name="date_range"][value="2026-06-01/2026-06-30"]', visible: :all)
      end
    end

    it "does not include data from another hotel" do
      room_type = create(:room_type, hotel: create(:hotel), quantity: 10)
      bookings = create_grouped_room_bookings(
        count: 5,
        hotel: room_type.hotel,
        booking_attributes: { status: "confirmed", check_in: start_date, check_out: end_date + 1.day },
        room_attributes: { room_type: room_type, subtotal: 100.0 }
      )

      get daily_occupancy_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Daily occupancy report")
      bookings.each { |booking| expect(response.body).not_to include(booking.confirmation_token) }
    end

    it "defaults blank first load to today" do
      travel_to(Time.zone.local(2026, 6, 15, 10, 0, 0)) do
        room_type = create(:room_type, hotel: hotel, quantity: 10)
        create(:room_inventory, room_type: room_type, date: Date.new(2026, 6, 1), quantity: 8, status: "open")
        create(:room_inventory, room_type: room_type, date: Date.new(2026, 6, 15), quantity: 9, status: "open")

        booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 6, 1), check_out: Date.new(2026, 6, 16), guest_name: "Month Guest")
        create(:booking_room, booking: booking, room_type: room_type, subtotal: 300)

        get daily_occupancy_hotel_reports_path(hotel)
        doc = Nokogiri::HTML(response.body)
        selected = doc.at_css('select[name="date_preset"] option[selected]')

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include("01 Jun 2026")
        expect(response.body).to include("15 Jun 2026")
        expect(selected["value"]).to eq("today")
      end
    end

    it "exports CSV" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      create_grouped_room_bookings(
        count: 2,
        hotel: hotel,
        booking_attributes: { status: "confirmed", check_in: start_date, check_out: end_date + 1.day },
        room_attributes: { room_type: room_type, subtotal: 150.0 }
      )

      get daily_occupancy_hotel_reports_path(hotel, format: :csv), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Date,Rooms Sold,Rooms Available,Occupancy %,Room Revenue,Average Daily Rate (ADR),Revenue per Available Room (RevPAR)")
    end

    it "exports PDF" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 120.0)

      get daily_occupancy_hotel_reports_path(hotel, format: :pdf), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include(".pdf")
    end

    it "exports XLSX" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 120.0)

      get daily_occupancy_hotel_reports_path(hotel, format: :xlsx), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.headers["Content-Disposition"]).to include(".xlsx")
      expect(response.body).to start_with("PK")
    end
  end

  describe "GET /outstanding_balance" do
    let(:start_date) { Date.new(2026, 5, 7) }
    let(:end_date) { Date.new(2026, 5, 8) }

    it "renders outstanding balance report for selected range" do
      unpaid = create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, guest_name: "Unpaid Guest", confirmation_token: "WS-UNPAID")
      unpaid_folio = create(:booking_folio, booking: unpaid, hotel: hotel)
      create(:folio_transaction, booking_folio: unpaid_folio, transaction_type: "charge", category: "accommodation", amount: 100)

      paid = create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", check_in: start_date, check_out: start_date + 1.day, guest_name: "Paid Guest", confirmation_token: "WS-PAID")
      paid_folio = create(:booking_folio, booking: paid, hotel: hotel)
      create(:folio_transaction, booking_folio: paid_folio, transaction_type: "charge", category: "accommodation", amount: 100)
      create(:folio_transaction, booking_folio: paid_folio, transaction_type: "payment", category: "cash", amount: 100)

      get outstanding_balance_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css("[data-slot='report-page'][data-report='outstanding-balance']")
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card", count: 2)
      expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']")
      expect(page).to have_css("h1", exact_text: "Outstanding balance report")
      expect(page).to have_css("select[name='date_preset'] option[value='this_year']", text: "This Year", visible: :all)
      expect(page).to have_link("WS-UNPAID", href: hotel_booking_workspace_path(hotel, unpaid, tab: "booking_details"))
      expect(page).to have_text("Unpaid Guest")
      expect(page).to have_no_text("Paid Guest")
    end

    it "uses one table with month divider rows for this year" do
      travel_to(Time.zone.local(2026, 7, 23, 10, 0, 0)) do
        [ Date.new(2026, 4, 14), Date.new(2026, 5, 14) ].each do |check_in|
          booking = create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: check_in, check_out: check_in + 1.day)
          folio = create(:booking_folio, booking: booking, hotel: hotel)
          create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100, posting_date: check_in)
        end

        get outstanding_balance_hotel_reports_path(hotel), params: { date_preset: "this_year" }

        page = Capybara.string(response.body)
        table = page.find("[aria-labelledby='outstanding-bookings-heading'] table")
        expect(page).to have_css("[aria-labelledby='outstanding-bookings-heading'] table", count: 1)
        expect(table).to have_css("[data-slot='report-month-group']", text: "April 2026")
        expect(table).to have_css("[data-slot='report-month-group']", text: "May 2026")
      end
    end

    it "exports CSV" do
      booking = create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, guest_name: "CSV Outstanding", confirmation_token: "WS-OB-CSV")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)

      get outstanding_balance_hotel_reports_path(hotel, format: :csv), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Guest Name,Booking Ref,Stay,Rooms,Room Numbers,Payment Status,Outstanding Amount,Notes")
      expect(response.body).to include("CSV Outstanding")
    end

    it "exports PDF" do
      booking = create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)

      get outstanding_balance_hotel_reports_path(hotel, format: :pdf), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include(".pdf")
    end

    it "exports XLSX" do
      booking = create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, guest_name: "Excel Outstanding")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)

      get outstanding_balance_hotel_reports_path(hotel, format: :xlsx), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.headers["Content-Disposition"]).to include(".xlsx")
      expect(response.body).to start_with("PK")
    end
  end

  describe "GET /deposit_liability" do
    let(:as_of_date) { Date.new(2026, 5, 20) }

    it "renders deposit liability report for selected as-of date" do
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: as_of_date + 1.day, check_out: as_of_date + 2.days, guest_name: "Deposit Guest", confirmation_token: "WS-DEP")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 250, posting_date: as_of_date - 1.day)

      ignored = create(:booking, hotel: hotel, status: "confirmed", check_in: as_of_date + 1.day, check_out: as_of_date + 2.days, guest_name: "Gateway Guest", confirmation_token: "WS-GATEWAY")
      ignored_folio = create(:booking_folio, booking: ignored, hotel: hotel)
      create(:folio_transaction, booking_folio: ignored_folio, transaction_type: :payment, category: "gateway_payment", amount: 250, posting_date: as_of_date - 1.day)

      get deposit_liability_hotel_reports_path(hotel), params: { as_of_date: as_of_date.to_s }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css("[data-slot='report-page'][data-report='deposit-liability']")
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card", count: 5)
      expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']")
      expect(page).to have_css("h1", exact_text: "Deposit liability report")
      expect(page).to have_link("WS-DEP", href: hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(page).to have_text("Deposit Guest")
      expect(page).to have_no_text("Gateway Guest")
    end

    it "renders one auto-submitting single-date picker for a custom date" do
      get deposit_liability_hotel_reports_path(hotel), params: { as_of_date: as_of_date.to_s }

      page = Capybara.string(response.body)
      expect(page).to have_css('input[name="as_of_date"][value="2026-05-20"]', visible: :all)
      expect(page).to have_no_css('input[name="date_range"]', visible: :all)
      picker = page.find('[data-panels-ui--date-picker-mode-value="single"]')
      expect(picker["data-action"]).to include("change->date-preset#submitDate")
      expect(page).to have_no_button("Apply")
      expect(page).to have_field("Time period", visible: :all)
      expect(page).to have_no_css("select[name='date_preset'] option[value='this_year']", visible: :all)
      expect(page).to have_no_css("select[name='date_preset'] option[value='all_time']", visible: :all)
      expect(page).to have_css("select[name='date_preset'] option[value='custom']", text: "Custom Date", visible: :all)
      expect(response.body).to include("As of date")
      expect(page).to have_no_field("As Of Date", visible: :all)
    end

    it "does not show bookings from another hotel" do
      other_hotel = create(:hotel)
      booking = create(:booking, hotel: other_hotel, status: "confirmed", check_in: as_of_date + 1.day, check_out: as_of_date + 2.days, guest_name: "Other Deposit Guest")
      folio = create(:booking_folio, booking: booking, hotel: other_hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 250, posting_date: as_of_date - 1.day)

      get deposit_liability_hotel_reports_path(hotel), params: { as_of_date: as_of_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Other Deposit Guest")
    end

    it "exports csv/xlsx/pdf" do
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: as_of_date + 1.day, check_out: as_of_date + 2.days, guest_name: "Export Deposit")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 250, posting_date: as_of_date - 1.day)

      get deposit_liability_hotel_reports_path(hotel, format: :csv), params: { as_of_date: as_of_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Guest Name,Booking Ref,Stay,Status,Rooms,Folio,Booking Payment,Earned,Refunds,Remaining Liability,Latest Payment Date")

      get deposit_liability_hotel_reports_path(hotel, format: :xlsx), params: { as_of_date: as_of_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")

      get deposit_liability_hotel_reports_path(hotel, format: :pdf), params: { as_of_date: as_of_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include(".pdf")
    end

    it "requires view_reports permission" do
      role.permissions.delete(Permission.find_by!(slug: "view_reports"))

      get deposit_liability_hotel_reports_path(hotel), params: { as_of_date: as_of_date.to_s }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end
  end

  describe "GET /daily_report" do
    let(:start_date) { Date.new(2026, 5, 6) }
    let(:end_date) { Date.new(2026, 5, 7) }

    it "renders the Daily Report page for the selected range" do
      create(:booking, hotel: hotel, status: "confirmed", source: "walk_in", total_amount: 100, tourism_tax_applied: true, tourism_tax_amount: 10, created_at: Time.zone.local(2026, 5, 6, 10, 0))

      get "/hotel/#{hotel.id}/reports/daily_report", params: { start_date: start_date.to_s, end_date: end_date.to_s }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Daily report")
      expect(page).to have_css("[data-slot='report-page'][data-report='daily-report']")
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card", count: 8)
      expect(page).to have_css("#daily-report-tabs.tabs-root--line nav.tabs-list--line")
      expect(page).to have_link("Cashier sales")
      expect(page.text).to include("Revenue (accrual)", "Bookings engaged", "Total charges", "Net revenue")
      expect(page.text).to include("Cashier sales (cash flow)", "Cash movements", "Total collected", "Total refunded", "Net cash")
      expect(page).to have_css("form[data-slot='report-toolbar']")
      expect(page).to have_css("[data-slot='report-export']")
      expect(page).to have_select("date_preset")
    end

    it "redirects the legacy Daily Revenue URL while preserving its query string" do
      get "/hotel/#{hotel.id}/reports/daily_revenue", params: { tab: "cashier", start_date: start_date.to_s }

      expect(response).to redirect_to(
        "/hotel/#{hotel.id}/reports/daily_report?tab=cashier&start_date=#{start_date}"
      )
    end

    it "requires view_reports permission" do
      role.permissions.delete(Permission.find_by!(slug: "view_reports"))

      get daily_report_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end

    it "skips Charge Register transformation for non-Revenue formats" do
      expect(HotelPortal::Reports::DailyReportChargeRegister).not_to receive(:new)

      %w[overview cashier].product([ nil, :csv, :xlsx, :pdf ]).each do |tab, format|
        get daily_report_hotel_reports_path(hotel, format: format), params: {
          tab: tab,
          start_date: start_date.to_s,
          end_date: end_date.to_s
        }

        expect(response).to have_http_status(:success)
      end
    end

    describe "revenue tab" do
      it "renders compact sentence-style report tables" do
        get daily_report_hotel_reports_path(hotel, tab: "revenue",
          start_date: start_date.to_s, end_date: start_date.to_s)

        page = Capybara.string(response.body)
        expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']", count: 3)
        expect(page.text).to include("Daily breakdown", "Revenue by source", "Revenue register")
        expect(page.text).to include("Other charges", "Total charges", "Net revenue", "Booking / folio", "Base amount", "Total amount")
      end

      it "queries the Charge Register scope once without filters" do
        expect(HotelPortal::Reports::DailyRevenueTransactionQuery).to receive(:new).once.and_call_original

        get daily_report_hotel_reports_path(hotel, tab: "revenue",
          start_date: start_date.to_s, end_date: start_date.to_s)

        expect(response).to have_http_status(:success)
      end

      it "combines generated tax with its charge in the Charge Register" do
        booking = create(:booking, hotel: hotel)
        room_type = create(:room_type, hotel: hotel, name: "Deluxe King")
        booking_room = create(:booking_room, booking: booking, room_type: room_type, room_number: "G01")
        folio = create(:booking_folio, booking: booking, booking_room: booking_room, hotel: hotel)
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
        charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
          category: "accommodation", amount: 480, posting_date: start_date)
        create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
          category: "tax", amount: 38.40, posting_date: start_date,
          metadata: { parent_folio_transaction_id: charge.id, tax_line: { type: "sst" } })

        get daily_report_hotel_reports_path(hotel, tab: "revenue",
          start_date: start_date.to_s, end_date: start_date.to_s)

        document = Nokogiri::HTML(response.body)
        rows = document.css('[data-testid="charge-register-row"]')
        headers = document.css("[aria-labelledby='revenue-register-heading'] thead th").map { |header| header.text.strip }

        expect(rows.size).to eq(1)
        expect(headers).to eq(
          [ "Date", "Service", "Booking / folio", "Guest", "Status", "Base amount", "Tax", "Total amount" ]
        )
        expect(rows.sole.css("td")[1].text.squish).to eq("Room Revenue ROOM")
        expect(rows.sole.css("td")[3].text.squish).to eq("#{booking.guest_name} G01 · Deluxe King")
        expect(rows.sole.css("td")[3].at_css("span")["class"].split).to include("whitespace-nowrap")
        expect(rows.sole.css("td")[5].text.squish).to eq("MYR 480.00")
        expect(rows.sole.css("td")[6].text.squish).to eq("MYR 38.40")
        expect(rows.sole.css("td")[7].text.squish).to eq("MYR 518.40")
        expect(rows.sole.text).not_to include("TAX_SST")
        expect(document.at_css("#revenue-register-heading").parent.text.squish).to include("Revenue register", "1 transaction")
      end

      it "shows the recorded time beneath the posting date when posted_at is unavailable" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        recorded_at = Time.find_zone!(user.time_zone).local(2026, 5, 6, 14, 35)
        create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
          category: "accommodation", amount: 480, posting_date: start_date,
          posted_at: nil, created_at: recorded_at)

        get daily_report_hotel_reports_path(hotel, tab: "revenue",
          start_date: start_date.to_s, end_date: start_date.to_s)

        date_cell = Nokogiri::HTML(response.body).at_css('[data-testid="charge-register-row"] td')

        expect(date_cell.text.squish).to eq("06 May 2026 2:35 PM")
      end

      it "does not show a room placeholder for an unassigned booking" do
        booking = create(:booking, hotel: hotel, guest_name: "Unassigned Guest")
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
          category: "accommodation", amount: 480, posting_date: start_date)

        get daily_report_hotel_reports_path(hotel, tab: "revenue",
          start_date: start_date.to_s, end_date: start_date.to_s)

        guest_cell = Nokogiri::HTML(response.body).at_css('[data-testid="charge-register-row"] td:nth-child(4)')

        expect(guest_cell.text.squish).to eq("Unassigned Guest")
      end

      it "highlights negative Revenue Register amounts without coloring zero tax" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment",
          category: "discount", amount: -40, posting_date: start_date)

        get daily_report_hotel_reports_path(hotel, tab: "revenue",
          start_date: start_date.to_s, end_date: start_date.to_s)

        row = Nokogiri::HTML(response.body).at_css('[data-testid="charge-register-row"]')
        amount_cells = row.css("td").to_a.last(3)

        expect(amount_cells[0]["class"]).to include("text-destructive")
        expect(amount_cells[1]["class"]).not_to include("text-destructive")
        expect(amount_cells[2]["class"]).to include("text-destructive")
      end

      it "keeps attached tax when filtering the Charge Register by category" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
        charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
          category: "accommodation", amount: 480, posting_date: start_date)
        create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
          category: "tax", amount: 38.40, posting_date: start_date,
          metadata: { parent_folio_transaction_id: charge.id, tax_line: { type: "sst" } })

        get daily_report_hotel_reports_path(hotel, tab: "revenue", category: "accommodation",
          start_date: start_date.to_s, end_date: start_date.to_s)

        row = Nokogiri::HTML(response.body).at_css('[data-testid="charge-register-row"]')

        expect(row.text.squish).to include("MYR 480.00", "MYR 38.40")
      end

      it "keeps attached tax when filtering the Charge Register by transaction code" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
        charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
          category: "accommodation", amount: 480, posting_date: start_date)
        create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
          category: "tax", amount: 38.40, posting_date: start_date,
          metadata: { parent_folio_transaction_id: charge.id, tax_line: { type: "sst" } })

        get daily_report_hotel_reports_path(hotel, tab: "revenue", transaction_code_id: room_code.id,
          start_date: start_date.to_s, end_date: start_date.to_s)

        row = Nokogiri::HTML(response.body).at_css('[data-testid="charge-register-row"]')

        expect(row.text.squish).to include("MYR 480.00", "MYR 38.40")
      end

      it "does not show a charge when filtering the Charge Register by tax category" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
        charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
          category: "accommodation", amount: 480, posting_date: start_date)
        create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
          category: "tax", amount: 38.40, posting_date: start_date,
          metadata: { parent_folio_transaction_id: charge.id, tax_line: { type: "sst" } })

        get daily_report_hotel_reports_path(hotel, tab: "revenue", category: "tax",
          start_date: start_date.to_s, end_date: start_date.to_s)

        document = Nokogiri::HTML(response.body)

        expect(document.css('[data-testid="charge-register-row"]')).to be_empty
        expect(document.at_css("#revenue-register-heading").parent.text.squish).to include("0 transactions")
      end

      it "shows the accrual charge register, scoped to charges/adjustments only" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        charge = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 120, posting_date: start_date)
        create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 360, posting_date: start_date)

        get daily_report_hotel_reports_path(hotel, tab: "revenue", start_date: start_date.to_s, end_date: start_date.to_s)

        expect(response).to have_http_status(:success)
        expect(response.body.scan('data-testid="charge-register-row"').size).to eq(1)
        expect(response.body).to include("120.00")
        expect(charge.amount).to eq(120)
      end

      it "shows positive adjustments as revenue increases" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "correction", amount: 25, posting_date: start_date)

        get daily_report_hotel_reports_path(hotel, tab: "revenue", start_date: start_date.to_s, end_date: start_date.to_s)

        expect(response.body).to include("+ MYR 25.00", "Increases revenue")
        expect(response.body).not_to include("- MYR 25.00")
      end

      it "includes adjustments and net revenue in Revenue by Source" do
        booking = create(:booking, hotel: hotel, source: "walk_in")
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: start_date)
        create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "discount", amount: -10, posting_date: start_date)

        get daily_report_hotel_reports_path(hotel, tab: "revenue", start_date: start_date.to_s, end_date: start_date.to_s)

        source_table = Nokogiri::HTML(response.body).at_css("[aria-labelledby='revenue-source-heading']")
        expect(source_table.text).to include("Adjustments", "Net revenue", "- MYR 10.00", "MYR 90.00")
      end
    end

    describe "cashier sales tab" do
      it "renders compact sentence-style report tables" do
        get daily_report_hotel_reports_path(hotel, tab: "cashier",
          start_date: start_date.to_s, end_date: start_date.to_s)

        page = Capybara.string(response.body)
        expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']", count: 4)
        expect(page.text).to include("Cashier summary", "Currency summary")

        document = Nokogiri::HTML(response.body)
        cashier_summary_headers = document
          .css("[aria-labelledby='cashier-summary-heading'] thead th")
          .map { |header| header.text.strip }
        currency_summary_headers = document
          .css("[aria-labelledby='currency-summary-heading'] thead th")
          .map { |header| header.text.strip }

        expect(cashier_summary_headers).to eq([ "Mode", "Currency", "Description", "Amount (in)", "Amount (out)", "Balance" ])
        expect(currency_summary_headers).to eq([ "Currency", "Description", "Amount (in)", "Amount (out)", "Balance" ])
      end

      it "splits Advance and Settlement payment rows" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        bank_code = hotel.transaction_codes.find_by!(system_key: "bank_payment")
        create(
          :folio_transaction,
          booking_folio: folio,
          transaction_type: "payment",
          category: "booking_payment",
          amount: 100,
          posting_date: start_date,
          user: nil,
          transaction_code: bank_code
        )
        create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 360, posting_date: start_date)

        get daily_report_hotel_reports_path(hotel, tab: "cashier", start_date: start_date.to_s, end_date: start_date.to_s)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Advance")
        expect(response.body).to include("Settlement")
        expect(response.body).to include("Remarks")

        headers = Nokogiri::HTML(response.body)
          .css("[aria-labelledby='cashier-advance-heading'] thead th")
          .map { |header| header.text.strip }
        expect(headers).to eq([
          "Date & time", "Reservation", "Guest details", "Folio", "Invoice",
          "Payment mode", "Received by", "Remarks", "Amount"
        ])

        advance_row = Nokogiri::HTML(response.body).at_css('[data-testid="advance-row"]')
        advance_cells = advance_row.css("td")
        expect(advance_cells.size).to eq(9)
        expect(advance_cells[2].text.squish).to include(booking.guest_name, "Room —")
        expect(advance_cells[3].text.strip).to eq(folio.folio_reference_display)
        expect(advance_cells[4].text.strip).to eq("—")
        expect(advance_row.text).to include("Bank Transfer Payment")

        settlement_row = Nokogiri::HTML(response.body).at_css('[data-testid="settlement-row"]')
        [ advance_row, settlement_row ].each do |row|
          expect(row.css("td").last["class"].split).to include("whitespace-nowrap")
        end
      end

      it "shows a refund under its resolved settlement mode" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "refund", amount: -25, posting_date: start_date, metadata: { refund_source: "cash" })

        get daily_report_hotel_reports_path(hotel, tab: "cashier", start_date: start_date.to_s, end_date: start_date.to_s)

        settlement_row = Nokogiri::HTML(response.body).at_css('[data-testid="settlement-row"]')
        expect(settlement_row.text).to include("Cash Payment")
        expect(settlement_row.text).not_to include("Refund")
      end

      it "hides Razorpay payments from cashier rows and summary metrics" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        razorpay_payment = create(:payment_transaction, booking: booking, gateway: "razorpay")
        create(
          :folio_transaction,
          booking_folio: folio,
          transaction_type: "payment",
          category: "gateway_payment",
          amount: 999,
          posting_date: start_date,
          description: "Hidden Razorpay payment",
          metadata: { payment_transaction_id: razorpay_payment.id, posting_source: "gateway_payment" }
        )
        create(
          :folio_transaction,
          booking_folio: folio,
          transaction_type: "payment",
          category: "cash",
          amount: 100,
          posting_date: start_date,
          description: "Visible front desk cash"
        )

        get daily_report_hotel_reports_path(hotel, tab: "cashier", start_date: start_date.to_s, end_date: start_date.to_s)

        document = Nokogiri::HTML(response.body)
        metrics = document.at_css('[aria-label="Cashier sales summary"]').text.squish
        expect(document.css('[data-testid="settlement-row"]').size).to eq(1)
        expect(response.body).to include("Visible front desk cash")
        expect(response.body).not_to include("Hidden Razorpay payment", "999.00")
        expect(metrics).to include("Cash movements 1", "Total collected MYR 100.00", "Net cash MYR 100.00")
      end
    end

    describe "csv export" do
      it "exports only the combined KPI summary on the overview tab" do
        get daily_report_hotel_reports_path(hotel, tab: "overview", format: :csv, start_date: start_date.to_s, end_date: start_date.to_s)

        expect(response.body).to include("Revenue (Accrual)", "Cashier Sales (Cash Flow)", "Net Revenue", "Net Cash")
        expect(response.body).not_to include("Posting Date", "Daily Breakdown")
      end

      it "exports the charge register on the revenue tab" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
        charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
          category: "accommodation", amount: 480, posting_date: start_date)
        create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
          category: "tax", amount: 38.40, posting_date: start_date,
          metadata: { parent_folio_transaction_id: charge.id, tax_line: { type: "sst" } })

        get daily_report_hotel_reports_path(hotel, tab: "revenue", format: :csv, start_date: start_date.to_s, end_date: start_date.to_s)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Daily Breakdown", "Revenue by Source", "Revenue Register", "Posting Date", "Transaction Code")
        expect(response.body).to include(
          "Posting Date,Posted At,Service Name,Transaction Code,Booking Ref,Folio Number,Guest Name,Room Number,Room Type,Relationship Status,Base Amount,Tax,Total Amount,Currency"
        )
        expect(response.body).to include("480.00,38.40,518.40,MYR")
        expect(response.body).not_to include("Transaction Type", "Category")
        expect(response.body).not_to include("TAX_SST")
        expect(response.body).not_to include("Cashier Summary")
      end

      it "exports the combined Advance + Settlement list on the cashier tab" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel, invoice_number: 20260506)
        cash_code = hotel.transaction_codes.find_by!(system_key: "cash_payment")
        create(
          :folio_transaction,
          booking_folio: folio,
          transaction_type: "payment",
          category: "cash",
          amount: 100,
          posting_date: start_date,
          posted_at: Time.zone.local(2026, 5, 6, 14, 30),
          description: "Cashier note",
          user: nil,
          transaction_code: cash_code
        )

        get daily_report_hotel_reports_path(hotel, tab: "cashier", format: :csv, start_date: start_date.to_s, end_date: start_date.to_s)

        expect(response).to have_http_status(:success)
        expect(response.body).to include(
          "Advance", "Settlement", "Cashier Summary", "Currency Summary",
          "Date & Time,Reservation,Guest,Room,Folio,Invoice,Payment Mode,Received By,Remarks,Currency,Amount",
          "Cash Payment", "20260506", "Cashier note"
        )
        expect(response.body).to include("#{start_date.iso8601}T")
        expect(response.body).not_to include("#{start_date.iso8601} 2026-")
        expect(response.body).not_to include("Room #", "Res. #", "Bill #")
        expect(response.body).not_to include("Daily Breakdown", "Revenue Register")
      end
    end

    describe "xlsx export" do
      it "downloads a genuine xlsx workbook for the active tab" do
        booking = create(:booking, hotel: hotel)
        folio = create(:booking_folio, booking: booking, hotel: hotel)
        create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: start_date)

        get daily_report_hotel_reports_path(hotel, tab: "revenue", format: :xlsx, start_date: start_date.to_s, end_date: start_date.to_s)

        expect(response).to have_http_status(:success)
        expect(response.content_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        expect(response.headers["Content-Disposition"]).to include(".xlsx")
        expect(response.body).to start_with("PK")
      end
    end
  end

  describe "GET /daily_revenue/cell" do
    let(:date) { Date.new(2026, 5, 6) }

    it "renders the underlying booking for an accommodation charge" do
      booking = create(:booking, hotel: hotel, source: "walk_in", confirmation_token: "WS-CELL")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 120, posting_date: date)

      get daily_revenue_cell_hotel_reports_path(hotel), params: { date: date.to_s, category: "accommodation", date_preset: "custom" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Accommodation")
      expect(response.body).to include("WS-CELL")
      expect(response.body).to include("120.00")
    end

    it "renders the underlying corporate account for an agent bank transfer" do
      agent_account = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent")
      create(:ar_payment, hotel: hotel, hotel_corporate_account: agent_account, payment_method: "bank_transfer", amount: 400, received_at: date)

      get daily_revenue_cell_hotel_reports_path(hotel), params: { date: date.to_s, category: "agent_bank_transfer", date_preset: "custom" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(agent_account.corporate_account.name)
      expect(response.body).to include("400.00")
    end

    it "requires view_reports permission" do
      role.permissions.delete(Permission.find_by!(slug: "view_reports"))

      get daily_revenue_cell_hotel_reports_path(hotel), params: { date: date.to_s, category: "accommodation" }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end

    it "returns bad_request when date is missing" do
      get daily_revenue_cell_hotel_reports_path(hotel), params: { category: "accommodation" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /daily_revenue/source" do
    let(:date) { Date.new(2026, 5, 6) }

    it "lists the bookings behind a source's booking count" do
      booking = create(:booking, hotel: hotel, source: "walk_in", guest_name: "Source Drilldown Guest", confirmation_token: "WS-SRC")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: date)

      get daily_revenue_source_bookings_hotel_reports_path(hotel), params: { source: "Walk-in", start_date: date.to_s, end_date: date.to_s, date_preset: "custom" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Walk-in bookings")
      expect(response.body).to include("WS-SRC")
      expect(response.body).to include("Source Drilldown Guest")
      expect(response.body).to include(hotel_booking_path(hotel, booking))
    end

    it "requires view_reports permission" do
      role.permissions.delete(Permission.find_by!(slug: "view_reports"))

      get daily_revenue_source_bookings_hotel_reports_path(hotel), params: { source: "Walk-in", start_date: date.to_s, end_date: date.to_s }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end
  end

  describe "GET /managers_flash" do
    it "redirects to daily_occupancy (merged into that report)" do
      get managers_flash_hotel_reports_path(hotel), params: { start_date: "2026-05-06", end_date: "2026-05-07" }

      expect(response).to redirect_to("/hotel/#{hotel.to_param}/reports/daily_occupancy?start_date=2026-05-06&end_date=2026-05-07")
    end
  end

  describe "GET /breakdown" do
    it "renders the financial breakdown table with taxes" do
      booking = create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", total_amount: 320, tax_lines: [ { "name" => "SST", "amount" => "20.00" } ], margin_amount: 30, net_amount: 290, created_at: Time.zone.local(2026, 5, 6, 12, 0))

      get breakdown_hotel_reports_path(hotel), params: { date_preset: "custom", start_date: "2026-05-01", end_date: "2026-05-31" }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Taxes")
      expect(response.body).to include("20.00")
      expect(page).to have_css("[data-slot='report-page'][data-report='financial-breakdown']")
      expect(page).to have_css(".panel-form-field[data-size='md'] input[type='search']")
      expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']")
      expect(page).to have_css("[data-slot='report-date-group']", text: "06 May 2026")
      expect(page).to have_link(
        "##{booking.confirmation_token}",
        href: hotel_booking_workspace_path(hotel, booking, tab: "booking_details")
      )
    end

    it "uses sentence-case report copy" do
      get breakdown_hotel_reports_path(hotel), params: {
        date_preset: "custom",
        start_date: "2026-05-01",
        end_date: "2026-05-31"
      }

      page = Capybara.string(response.body)
      expect(page).to have_css("h1", exact_text: "Financial breakdown")
      expect(page).to have_css("turbo-frame#breakdown_results .panel-page-header__caption")
      caption = page.find(".panel-page-header__caption")
      expect(caption).to have_text(hotel.name)
      expect(caption).to have_text("01 May 2026 - 31 May 2026")
      expect(page.all("table.panel-table thead th").map(&:text)).to eq(
        [ "Booking reference", "Guest name", "Status", "Gross price", "Taxes", "Margin", "Net payout" ]
      )
    end

    it "renders essential booking status at a readable badge size" do
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", total_amount: 320, margin_amount: 30, net_amount: 290)

      get breakdown_hotel_reports_path(hotel)

      page = Capybara.string(response.body)
      expect(page).to have_css(".panel-badge-rounded[data-size='lg']", text: "confirmed")
    end

    it "exports xlsx and pdf" do
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", total_amount: 300, margin_amount: 30, net_amount: 270, created_at: Time.zone.local(2026, 5, 6, 12, 0))

      get breakdown_hotel_reports_path(hotel, format: :xlsx), params: { date_preset: "custom", start_date: "2026-05-01", end_date: "2026-05-31" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")

      get breakdown_hotel_reports_path(hotel, format: :pdf), params: { date_preset: "custom", start_date: "2026-05-01", end_date: "2026-05-31" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
    end
  end

  describe "GET /payouts" do
    it "renders both payout panels and the tab-aware breadcrumb" do
      get payouts_hotel_reports_path(hotel), params: { tab: "paid" }

      expect(response).to have_http_status(:success)
      page = Capybara.string(response.body)
      expect(page).to have_css('[data-panels-ui--tabs-active-value="paid"]')
      expect(page).to have_css('[data-testid="payouts-upcoming-panel"]', visible: :all)
      expect(page).to have_css('[data-testid="payouts-paid-panel"]')
      expect(page).to have_css('[data-panels-ui--breadcrumb-target="tabLabel"]', text: "Paid History")
    end

    it "falls back to upcoming for an unknown tab" do
      get payouts_hotel_reports_path(hotel), params: { tab: "unknown" }

      expect(response).to have_http_status(:success)
      page = Capybara.string(response.body)
      expect(page).to have_css('[data-panels-ui--tabs-active-value="upcoming"]')
      expect(page).to have_css(
        '[data-panels-ui--breadcrumb-target="tabLabel"]',
        text: "Upcoming & Processing"
      )
    end

    it "uses an auto-submitting two-month range picker for paid history" do
      create(
        :payout_batch,
        hotel: hotel,
        status: "paid",
        period_start: Date.new(2026, 5, 1),
        period_end: Date.new(2026, 5, 31)
      )

      get payouts_hotel_reports_path(hotel), params: {
        tab: "paid",
        paid_date_range: "2026-05-01/2026-05-31"
      }

      page = Capybara.string(response.body)
      picker = page.find('[data-panels-ui--date-picker-mode-value="range"]')
      expect(response).to have_http_status(:success)
      expect(picker["data-panels-ui--date-picker-months-value"]).to eq("2")
      expect(picker["data-action"]).to include("change->date-preset#submitDate")
      expect(page).to have_css('input[name="paid_date_range"][value="2026-05-01/2026-05-31"]', visible: :all)
      expect(page).to have_no_button("Filter")
      expect(page).to have_link(
        "Export CSV",
        href: payouts_hotel_reports_path(
          hotel,
          tab: "paid",
          paid_start_date: Date.new(2026, 5, 1),
          paid_end_date: Date.new(2026, 5, 31),
          format: :csv
        )
      )
    end

    it "exports csv/xlsx/pdf for upcoming tab" do
      create(:booking, hotel: hotel, status: "completed", payment_status: "captured", net_amount: 120, checked_out_at: Time.zone.local(2026, 5, 7, 10, 0), payout_batch_id: nil)

      get payouts_hotel_reports_path(hotel, format: :csv), params: { tab: "upcoming" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")

      get payouts_hotel_reports_path(hotel, format: :xlsx), params: { tab: "upcoming" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")

      get payouts_hotel_reports_path(hotel, format: :pdf), params: { tab: "upcoming" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
    end

    it "exports paid history when the paid tab is requested" do
      create(:payout_batch, hotel: hotel, status: "paid", payout_reference: "PAID-EXPORT")

      get payouts_hotel_reports_path(hotel, format: :csv), params: { tab: "paid" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("PAID-EXPORT")
    end
  end

  describe "GET /refund_report" do
    let(:start_date) { Date.new(2026, 5, 7) }
    let(:end_date) { Date.new(2026, 5, 8) }

    it "renders refund records for selected range" do
      booking = create(:booking, hotel: hotel, guest_name: "Refund Guest", confirmation_token: "WS-RFD")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      room_type = create(:room_type, hotel: hotel, name: "Deluxe King")
      create(:booking_room, booking: booking, room_type: room_type)
      refund_request = create(:refund_request, booking: booking, status: "completed", refund_amount: 80.0, reason: "Guest cancelled")
      create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: "payment",
        category: "refund",
        amount: -80.0,
        posting_date: start_date,
        metadata: { refund_request_id: refund_request.id, refund_source: "bank_transfer", reference: "BNK-123" }
      )
      create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: "payment",
        category: "cash",
        amount: 80.0,
        posting_date: start_date
      )

      get refund_report_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css("[data-slot='report-page'][data-report='refund']")
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card", count: 2)
      expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']")
      expect(page).to have_css("h1", exact_text: "Monthly refund report")
      expect(page).to have_text("Refund Guest")
      expect(page).to have_text("WS-RFD")
      expect(page).to have_text("Deluxe King")
      expect(page).to have_text("Bank transfer")
      expect(page).to have_text("BNK-123")
      expect(page).to have_text("Guest cancelled")
      expect(page).to have_text("80.00")
    end

    it "does not include refunds from another hotel or outside range" do
      booking = create(:booking, hotel: hotel, guest_name: "Shown Guest")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: "payment",
        category: "refund",
        amount: -50.0,
        posting_date: start_date
      )

      other_booking = create(:booking, hotel: create(:hotel), guest_name: "Other Hotel Guest")
      other_folio = create(:booking_folio, booking: other_booking, hotel: other_booking.hotel)
      create(
        :folio_transaction,
        booking_folio: other_folio,
        transaction_type: "payment",
        category: "refund",
        amount: -75.0,
        posting_date: start_date
      )

      old_booking = create(:booking, hotel: hotel, guest_name: "Old Refund Guest")
      old_folio = create(:booking_folio, booking: old_booking, hotel: hotel)
      create(
        :folio_transaction,
        booking_folio: old_folio,
        transaction_type: "payment",
        category: "refund",
        amount: -30.0,
        posting_date: start_date - 3.days
      )

      get refund_report_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Shown Guest")
      expect(response.body).not_to include("Other Hotel Guest")
      expect(response.body).not_to include("Old Refund Guest")
    end

    it "groups individual this year refunds under their month" do
      booking = create(:booking, hotel: hotel, guest_name: "Monthly Guest", confirmation_token: "WS-MON")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: "payment",
        category: "refund",
        amount: -40.0,
        posting_date: Date.new(2026, 5, 7)
      )

      get refund_report_hotel_reports_path(hotel), params: { date_preset: "this_year" }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css("thead th", exact_text: "Date")
      expect(page).to have_css("[data-slot='report-month-group']", text: "May 2026")
      expect(page).to have_text("07 May 2026")
      expect(page).to have_text("Monthly Guest")
      expect(page).to have_no_text("January 2026")
    end
  end

  describe "GET /journal_batches" do
    it "uses an auto-submitting two-month range picker and CSV dropdown" do
      batch = create(
        :journal_batch,
        hotel: hotel,
        business_date: Date.new(2026, 5, 7),
        status: "finalized",
        finalized_at: Time.zone.local(2026, 5, 8, 2, 30)
      )
      create(
        :journal_batch_entry,
        journal_batch: batch,
        gl_code: "4010",
        transaction_type: "charge",
        debit_amount: 125,
        credit_amount: 125,
        description: "Room charge summary"
      )

      get journal_batches_hotel_reports_path(hotel), params: { date_range: "2026-05-01/2026-05-31" }

      page = Capybara.string(response.body)
      picker = page.find('[data-panels-ui--date-picker-mode-value="range"]')
      expect(response).to have_http_status(:success)
      expect(page).to have_css("[data-slot='report-page'][data-report='journal-batches']")
      expect(page).to have_css("h1", exact_text: "Journal batches")
      caption = page.find(".panel-page-header__caption")
      expect(caption).to have_text(hotel.name)
      expect(caption).to have_text("01 May 2026 - 31 May 2026")
      expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']")
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card", count: 3)
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card__detail", count: 3)
      expect(picker["data-panels-ui--date-picker-months-value"]).to eq("2")
      expect(picker["data-action"]).to include("change->date-preset#submitDate")
      expect(page).to have_no_button("Filter")
      expect(page).to have_text("07 May 2026")
      expect(page).to have_text("Finalized at")
      expect(page).to have_css(".panel-badge[data-variant='success']", text: "Finalized")
      expect(page).to have_css("thead th", exact_text: "General ledger code (GL code)")
      expect(page).to have_text("4010")
      expect(page).to have_text("Room charge summary")
      expect(page).to have_text("125.00", count: 6)
      expect(page).to have_link("Export CSV", href: journal_batches_hotel_reports_path(hotel, start_date: "2026-05-01", end_date: "2026-05-31", format: :csv))
      expect(page).to have_link("Export Excel", href: journal_batches_hotel_reports_path(hotel, start_date: "2026-05-01", end_date: "2026-05-31", format: :xlsx))
      expect(page).to have_link("Export PDF", href: journal_batches_hotel_reports_path(hotel, start_date: "2026-05-01", end_date: "2026-05-31", format: :pdf))
      expect(page).to have_css('[data-controller~="panels-ui--dropdown-menu"]')
    end

    it "exports XLSX and PDF" do
      create(:journal_batch, hotel: hotel, business_date: Date.new(2026, 5, 7))

      get journal_batches_hotel_reports_path(hotel, format: :xlsx), params: { start_date: "2026-05-01", end_date: "2026-05-31" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")

      get journal_batches_hotel_reports_path(hotel, format: :pdf), params: { start_date: "2026-05-01", end_date: "2026-05-31" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
    end
  end

  describe "GET /folio_ledger exports" do
    let(:posting_date) { Date.new(2026, 5, 7) }

    before do
      booking = create(:booking, hotel: hotel)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, posting_date: posting_date, amount: 120)
    end

    it "exports genuine XLSX and branded PDF files" do
      get folio_ledger_hotel_reports_path(hotel, format: :xlsx), params: { start_date: posting_date.to_s, end_date: posting_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")

      get folio_ledger_hotel_reports_path(hotel, format: :pdf), params: { start_date: posting_date.to_s, end_date: posting_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
    end
  end
end
