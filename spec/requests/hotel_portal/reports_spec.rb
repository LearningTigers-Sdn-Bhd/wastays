# frozen_string_literal: true

require 'rails_helper'
require "nokogiri"

RSpec.describe "HotelPortal::Reports", type: :request do
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, plan: plan, allow_boat_information: false) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  def enable_plan_feature(slug)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: slug), enabled: true)
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

  describe "GET /index" do
    it "returns http success" do
      get "/hotel/#{hotel.id}/reports"
      expect(response).to have_http_status(:success)
    end

    it "exports financial performance csv/xls/pdf" do
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", total_amount: 300, margin_amount: 30, net_amount: 270, created_at: Time.zone.local(2026, 5, 6, 12, 0))

      get "/hotel/#{hotel.id}/reports.csv"
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")

      get "/hotel/#{hotel.id}/reports.xls"
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")

      get "/hotel/#{hotel.id}/reports.pdf"
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
    end

    it "parses date_range and preserves the query in resolved export links" do
      get hotel_reports_path(hotel), params: { date_range: "2026-05-06/2026-05-08", q: "A&B" }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css('select[name="date_preset"] option[selected][value="custom"]')
      expect(page).to have_css('input[name="date_range"][value="2026-05-06/2026-05-08"]', visible: :all)
      expect(page).to have_link("Export CSV", href: hotel_reports_path(hotel, start_date: "2026-05-06", end_date: "2026-05-08", q: "A&B", date_preset: "custom", format: :csv))
    end

    it "prefers resolved export dates over a relative preset" do
      get hotel_reports_path(hotel), params: {
        date_preset: "today",
        start_date: "2026-05-06",
        end_date: "2026-05-08"
      }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_link(
        "Export CSV",
        href: hotel_reports_path(
          hotel,
          start_date: "2026-05-06",
          end_date: "2026-05-08",
          q: nil,
          date_preset: "today",
          format: :csv
        )
      )
    end
  end

  describe "GET /guest_reports" do
    let(:start_date) { Date.new(2026, 5, 7) }
    let(:end_date) { Date.new(2026, 5, 8) }

    it "renders the guest reports page for the selected date range" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Arriving Guest", confirmation_token: "WS-ARR")
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: start_date, guest_name: "Departing Guest", confirmation_token: "WS-DEP")
      create(:booking, hotel: hotel, status: "confirmed", check_in: end_date + 1.day, check_out: end_date + 2.days, guest_name: "Wrong Date")

      get guest_reports_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Guest Reports")
      expect(response.body).to include("Expected Arrivals")
      expect(response.body).to include("Arriving Guest")
      expect(response.body).not_to include("Wrong Date")
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
      expect(response.body).to include("Guest Reports")
      expect(response.body).to include("Expected Arrivals")
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
      expect(response.body).to include("Guest Reports")
      expect(response.body).to include("In-House Guests")
      expect(response.body).to include("In House Guest")
    end

    it "renders registration cards tab with date filtering and no export menu" do
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
      expect(response.body).to include("Registration Cards")
      expect(response.body).to include("Current GRC")
      expect(response.body).not_to include("Old GRC")
      expect(response.body).to include(hotel_booking_guest_registration_card_path(hotel, matching_booking))
      expect(response.body).not_to include("Export PDF")
      expect(response.body).not_to include("Export Excel")
      expect(response.body).not_to include("Export CSV")
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
        expect(response.body).to include("In-House Guests")
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

      get guest_reports_hotel_reports_path(hotel, format: :xls), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")
      expect(response.headers["Content-Disposition"]).to include(".xls")
      expect(response.body).to include('ss:Name="Arrivals"')
      expect(response.body).not_to include('ss:Name="Departures"')
      expect(response.body).to include("Excel Guest")
    end
  end

  describe "GET /non_national" do
    let(:start_date) { Date.new(2026, 7, 1) }
    let(:end_date) { Date.new(2026, 7, 1) }

    it "renders the non-national report with in-house foreign guests only" do
      booking = create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, checked_in_at: Time.zone.local(2026, 6, 30, 15, 45, 0), guest_name: "Kenji Sato", guest_country: "Japan", guest_home_address: "1 Chome-1-2 Oshiage, Sumida City, Tokyo, Japan", confirmation_token: "WS-NONNAT")
      guest = create(:guest, date_of_birth: Date.new(1990, 5, 20))
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Ahmad", guest_country: "Malaysia")

      get non_national_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Non-National Report")
      expect(response.body).to include("Kenji Sato")
      expect(response.body).to include("Japan")
      expect(response.body).to include("1 Chome-1-2 Oshiage, Sumida City, Tokyo, Japan")
      expect(response.body).to include("Check In Time")
      expect(response.body).to include("Date of Birth")
      expect(response.body).to include("20 May 1990")
      expect(response.body).not_to include("Ahmad")
    end

    it "exports csv for the selected range" do
      booking = create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, checked_in_at: Time.zone.local(2026, 6, 30, 14, 10, 0), guest_name: "CSV Foreigner", guest_country: "Singapore", guest_home_address: "25 Beach Road, Singapore", confirmation_token: "WS-CSV-NONNAT")
      guest = create(:guest, date_of_birth: Date.new(1988, 12, 5))
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      get non_national_hotel_reports_path(hotel, format: :csv), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.headers["Content-Disposition"]).to include("non-national-report")
      expect(response.body).to include("Full Name,Nationality,Date of Birth,Home Address,Check In Date,Check In Time,Check Out Date")
      expect(response.body).to include("CSV Foreigner")
      expect(response.body).to include("Singapore")
      expect(response.body).to include("25 Beach Road, Singapore")
      expect(response.body).to include("05 Dec 1988")
      expect(response.body).to include("10:10 PM")
    end

    it "shows the actual check-in date for overlapping guests" do
      create(:booking, hotel: hotel, status: "checked_in", check_in: Date.new(2026, 6, 30), check_out: Date.new(2026, 7, 2), guest_name: "Overlap Guest", guest_country: "Japan", tourism_tax_amount: 10)

      get non_national_hotel_reports_path(hotel), params: { date_preset: "this_month" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Overlap Guest")
      expect(response.body).to include("30 Jun 2026")
    end
  end

  describe "GET /tourism_tax" do
    let(:start_date) { Date.new(2026, 7, 1) }
    let(:end_date) { Date.new(2026, 7, 1) }

    it "renders the tourism tax report with due and collected figures" do
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Kenji Sato", guest_country: "Japan", tourism_tax_amount: 20, tourism_tax_collected: true)
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Ahmad", guest_country: "Malaysia", tourism_tax_amount: 10, tourism_tax_collected: true)

      get tourism_tax_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Tourism Tax Report")
      expect(response.body).to include("Kenji Sato")
      expect(response.body).to include("MYR 20.00")
    end

    it "exports csv for the selected range" do
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "CSV Foreigner", guest_country: "Singapore", tourism_tax_amount: 10, tourism_tax_collected: false, confirmation_token: "WS-CSV-TTX")

      get tourism_tax_hotel_reports_path(hotel, format: :csv), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.headers["Content-Disposition"]).to include("tourism-tax-report")
      expect(response.body).to include("Guest Name,Nationality,Booking Ref,Check In,Check Out,Nights,Tax Due (MYR),Tax Collected (MYR),Collection Status")
      expect(response.body).to include("CSV Foreigner")
      expect(response.body).to include("Pending")
    end
  end

  describe "GET /extra_charge" do
    it "renders the extra charge report page" do
      booking = create(:booking, hotel: hotel, guest_name: "FB Guest")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "fb", description: "Restaurant", amount: 20, posting_date: Date.new(2026, 6, 15))

      get extra_charge_hotel_reports_path(hotel), params: {
        start_date: "2026-06-15",
        end_date: "2026-06-15"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Extra Charge Report")
      expect(response.body).to include("FB Guest")
      expect(response.body).to include("Restaurant")
      expect(response.body).to include("MYR 20.00")
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

    it "exports csv for the active tab only" do
      booking = create(:booking, hotel: hotel, guest_name: "CSV Guest")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "fb", description: "Restaurant", amount: 20, posting_date: Date.new(2026, 6, 15))

      get extra_charge_hotel_reports_path(hotel, format: :csv), params: {
        tab: "fb",
        start_date: "2026-06-15",
        end_date: "2026-06-15"
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.headers["Content-Disposition"]).to include("extra-charge-report-fb")
      expect(response.body).to include("Restaurant")
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

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Daily Occupancy Report")
      expect(response.body).to include("Rooms Sold")
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
      expect(response.body).to include("Daily Occupancy Report")
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

    it "exports XLS" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 120.0)

      get daily_occupancy_hotel_reports_path(hotel, format: :xls), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")
      expect(response.headers["Content-Disposition"]).to include(".xls")
      expect(response.body).to include('ss:Name="Summary"')
      expect(response.body).to include('ss:Name="Daily Occupancy"')
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

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Outstanding Balance Report")
      expect(response.body).to include("Unpaid Guest")
      expect(response.body).not_to include("Paid Guest")
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

    it "exports XLS" do
      booking = create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, guest_name: "Excel Outstanding")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)

      get outstanding_balance_hotel_reports_path(hotel, format: :xls), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")
      expect(response.headers["Content-Disposition"]).to include(".xls")
      expect(response.body).to include('ss:Name="Summary"')
      expect(response.body).to include('ss:Name="Outstanding Balances"')
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

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Deposit Liability Report")
      expect(response.body).to include("Deposit Guest")
      expect(response.body).not_to include("Gateway Guest")
    end

    it "renders one auto-submitting single-date picker for a custom date" do
      get deposit_liability_hotel_reports_path(hotel), params: { as_of_date: as_of_date.to_s }

      page = Capybara.string(response.body)
      expect(page).to have_css('input[name="as_of_date"][value="2026-05-20"]', visible: :all)
      expect(page).to have_no_css('input[name="date_range"]', visible: :all)
      picker = page.find('[data-panels-ui--date-picker-mode-value="single"]')
      expect(picker["data-action"]).to include("change->date-preset#submitDate")
      expect(page).to have_no_button("Apply")
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

    it "exports csv/xls/pdf" do
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: as_of_date + 1.day, check_out: as_of_date + 2.days, guest_name: "Export Deposit")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 250, posting_date: as_of_date - 1.day)

      get deposit_liability_hotel_reports_path(hotel, format: :csv), params: { as_of_date: as_of_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Guest Name,Booking Ref,Stay,Status,Rooms,Folio,Booking Payment,Earned,Refunds,Remaining Liability,Latest Payment Date")

      get deposit_liability_hotel_reports_path(hotel, format: :xls), params: { as_of_date: as_of_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")
      expect(response.body).to include('ss:Name="Deposit Liability"')

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

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Daily Report")
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
          [ "Date", "Service", "Booking / Folio", "Guest", "Status", "Base Amount", "Tax", "Total Amount" ]
        )
        expect(rows.sole.css("td")[1].text.squish).to eq("Room Revenue ROOM")
        expect(rows.sole.css("td")[3].text.squish).to eq("#{booking.guest_name} G01 · Deluxe King")
        expect(rows.sole.css("td")[3].at_css("span")["class"].split).to include("whitespace-nowrap")
        expect(rows.sole.css("td")[5].text.squish).to eq("MYR 480.00")
        expect(rows.sole.css("td")[6].text.squish).to eq("MYR 38.40")
        expect(rows.sole.css("td")[7].text.squish).to eq("MYR 518.40")
        expect(rows.sole.text).not_to include("TAX_SST")
        expect(document.at_css("#revenue-register-heading").parent.text.squish).to include("Revenue Register", "1 transaction")
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
        expect(source_table.text).to include("Adjustments", "Net Revenue", "- MYR 10.00", "MYR 90.00")
      end
    end

    describe "cashier sales tab" do
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
          "Date & Time", "Reservation", "Guest Details", "Folio", "Invoice",
          "Payment Mode", "Received By", "Remarks", "Amount"
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
        metrics = document.at_css('[aria-label="Cashier Sales metrics"]').text.squish
        expect(document.css('[data-testid="settlement-row"]').size).to eq(1)
        expect(response.body).to include("Visible front desk cash")
        expect(response.body).not_to include("Hidden Razorpay payment", "999.00")
        expect(metrics).to include("Cash Movements 1", "Total Collected MYR 100.00", "Net Cash MYR 100.00")
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
      expect(response.body).to include("Walk-in Bookings")
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
    let(:start_date) { Date.new(2026, 5, 6) }
    let(:end_date) { Date.new(2026, 5, 7) }

    it "renders the manager flash report for the selected range" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      create_grouped_room_bookings(
        count: 2,
        hotel: hotel,
        booking_attributes: { status: "confirmed", check_in: start_date, check_out: end_date + 1.day },
        room_attributes: { room_type: room_type, subtotal: 200.0 }
      )

      get managers_flash_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Manager Flash Report")
      expect(response.body).to include("Total Revenue")
    end

    it "exports csv/xls/pdf" do
      get managers_flash_hotel_reports_path(hotel, format: :csv), params: { start_date: start_date.to_s, end_date: end_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")

      get managers_flash_hotel_reports_path(hotel, format: :xls), params: { start_date: start_date.to_s, end_date: end_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")

      get managers_flash_hotel_reports_path(hotel, format: :pdf), params: { start_date: start_date.to_s, end_date: end_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
    end
  end

  describe "GET /breakdown" do
    it "renders the financial breakdown table with taxes" do
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", total_amount: 320, tax_lines: [ { "name" => "SST", "amount" => "20.00" } ], margin_amount: 30, net_amount: 290, created_at: Time.zone.local(2026, 5, 6, 12, 0))

      get breakdown_hotel_reports_path(hotel), params: { date_preset: "custom", start_date: "2026-05-01", end_date: "2026-05-31" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Taxes")
      expect(response.body).to include("20.00")
    end

    it "exports xls and pdf" do
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", total_amount: 300, margin_amount: 30, net_amount: 270, created_at: Time.zone.local(2026, 5, 6, 12, 0))

      get breakdown_hotel_reports_path(hotel, format: :xls), params: { date_preset: "custom", start_date: "2026-05-01", end_date: "2026-05-31" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")

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

    it "exports csv/xls/pdf for upcoming tab" do
      create(:booking, hotel: hotel, status: "completed", payment_status: "captured", net_amount: 120, checked_out_at: Time.zone.local(2026, 5, 7, 10, 0), payout_batch_id: nil)

      get payouts_hotel_reports_path(hotel, format: :csv), params: { tab: "upcoming" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")

      get payouts_hotel_reports_path(hotel, format: :xls), params: { tab: "upcoming" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")

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

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Monthly Refund Report")
      expect(response.body).to include("Refund Guest")
      expect(response.body).to include("WS-RFD")
      expect(response.body).to include("Deluxe King")
      expect(response.body).to include("Bank transfer")
      expect(response.body).to include("BNK-123")
      expect(response.body).to include("Guest cancelled")
      expect(response.body).to include("80.00")
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

    it "groups this year refunds by month" do
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

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Month")
      expect(response.body).to include("May 2026")
      expect(response.body).not_to include("07 May 2026")
    end
  end

  describe "GET /journal_batches" do
    it "uses an auto-submitting two-month range picker and CSV dropdown" do
      get journal_batches_hotel_reports_path(hotel), params: { date_range: "2026-05-01/2026-05-31" }

      page = Capybara.string(response.body)
      picker = page.find('[data-panels-ui--date-picker-mode-value="range"]')
      expect(response).to have_http_status(:success)
      expect(picker["data-panels-ui--date-picker-months-value"]).to eq("2")
      expect(picker["data-action"]).to include("change->date-preset#submitDate")
      expect(page).to have_no_button("Filter")
      expect(page).to have_link("Export CSV", href: journal_batches_hotel_reports_path(hotel, start_date: "2026-05-01", end_date: "2026-05-31", format: :csv))
      expect(page).to have_css('[data-controller~="panels-ui--dropdown-menu"]')
    end
  end
end
