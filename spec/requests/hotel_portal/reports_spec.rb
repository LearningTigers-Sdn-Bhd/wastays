# frozen_string_literal: true

require 'rails_helper'
require "nokogiri"

RSpec.describe "HotelPortal::Reports", type: :request do
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, plan: plan) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  def enable_plan_feature(slug)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: slug), enabled: true)
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
  end

  describe "GET /arrivals_departures" do
    let(:start_date) { Date.new(2026, 5, 7) }
    let(:end_date) { Date.new(2026, 5, 8) }

    it "renders the guest reports page for the selected date range" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Arriving Guest", confirmation_token: "WS-ARR")
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: start_date, guest_name: "Departing Guest", confirmation_token: "WS-DEP")
      create(:booking, hotel: hotel, status: "confirmed", check_in: end_date + 1.day, check_out: end_date + 2.days, guest_name: "Wrong Date")

      get arrivals_departures_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Guest Reports")
      expect(response.body).to include("Expected Arrivals")
      expect(response.body).to include("Arriving Guest")
      expect(response.body).not_to include("Wrong Date")
    end

    it "renders guest reports heading and defaults invalid tab to arrivals" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Arriving Guest")
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: start_date + 1.day, guest_name: "In House Guest")

      get arrivals_departures_hotel_reports_path(hotel), params: {
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

      get arrivals_departures_hotel_reports_path(hotel), params: {
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

      get arrivals_departures_hotel_reports_path(hotel), params: {
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

    it "does not export registration cards from guest reports" do
      get arrivals_departures_hotel_reports_path(hotel, format: :csv), params: { tab: "registration_cards" }

      expect(response).to have_http_status(:not_acceptable)
    end

    it "keeps today selected when switching guest report tabs" do
      travel_to(Time.zone.local(2026, 6, 15, 10, 0, 0)) do
        create(:booking, hotel: hotel, status: "checked_in", check_in: Date.new(2026, 6, 14), check_out: Date.new(2026, 6, 16), guest_name: "In House Guest")

        get arrivals_departures_hotel_reports_path(hotel), params: { tab: "in_house" }
        doc = Nokogiri::HTML(response.body)
        selected = doc.at_css('select[name="date_preset"] option[selected]')

        expect(response).to have_http_status(:success)
        expect(selected["value"]).to eq("today")
        expect(response.body).to include("In-House Guests")
      end
    end

    it "does not show bookings from another hotel" do
      create(:booking, hotel: create(:hotel), status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Other Hotel Guest")

      get arrivals_departures_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Other Hotel Guest")
    end

    it "defaults guest reports first load to today" do
      travel_to(Time.zone.local(2026, 6, 15, 10, 0, 0)) do
        create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 6, 15), check_out: Date.new(2026, 6, 16), guest_name: "Today Arrival")
        create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 6, 1), check_out: Date.new(2026, 6, 2), guest_name: "Earlier Month Arrival")

        get arrivals_departures_hotel_reports_path(hotel)
        doc = Nokogiri::HTML(response.body)
        selected = doc.at_css('select[name="date_preset"] option[selected]')

        expect(response).to have_http_status(:success)
        expect(response.body).to include("15 Jun")
        expect(selected["value"]).to eq("today")
      end
    end

    it "falls back to today when both start and end dates are invalid" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current, check_out: Date.current + 1.day, guest_name: "Today Guest")

      get arrivals_departures_hotel_reports_path(hotel), params: { start_date: "bad-start", end_date: "bad-end" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(Date.current.strftime("%d %b"))
    end

    it "supports single-date legacy param for backward compatibility" do
      date = Date.new(2026, 5, 10)
      create(:booking, hotel: hotel, status: "confirmed", check_in: date, check_out: date + 1.day, guest_name: "Legacy Date Guest")

      get arrivals_departures_hotel_reports_path(hotel), params: { date: date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("10 May")
    end

    it "aligns end date to start date when start date is later than end date" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 10), check_out: Date.new(2026, 5, 11), guest_name: "Start Date Guest")
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 8), check_out: Date.new(2026, 5, 9), guest_name: "Old Date Guest")

      get arrivals_departures_hotel_reports_path(hotel), params: {
        start_date: "2026-05-10",
        end_date: "2026-05-09"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("10 May")
      expect(response.body).not_to include("08 May")
    end

    it "exports CSV for the selected range" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "CSV Guest", confirmation_token: "WS-CSV")

      get arrivals_departures_hotel_reports_path(hotel, format: :csv), params: {
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

      get arrivals_departures_hotel_reports_path(hotel, format: :csv), params: {
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

      get arrivals_departures_hotel_reports_path(hotel, format: :pdf), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include(".pdf")
    end

    it "exports Excel for the default arrivals tab" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Excel Guest", confirmation_token: "WS-XLS")

      get arrivals_departures_hotel_reports_path(hotel, format: :xls), params: {
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

  describe "GET /guest_registration_cards" do
    it "renders guest registration cards report with view and print links" do
      booking = create(:booking, hotel: hotel, guest_name: "Jane GRC", check_in: Date.new(2026, 5, 7), check_out: Date.new(2026, 5, 8))
      create(:guest_registration_card, :signed, booking: booking, hotel: hotel)

      get guest_registration_cards_hotel_reports_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Guest Registration Cards")
      expect(response.body).to include("Jane GRC")
      expect(response.body).to include(booking.guest_registration_card_number_display)
      expect(response.body).to include(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(response.body).to include("Print / Save as PDF")
    end

    it "filters by status and searches guest registration cards" do
      signed_booking = create(:booking, hotel: hotel, guest_name: "Jane GRC", confirmation_token: "GRC-JANE")
      draft_booking = create(:booking, hotel: hotel, guest_name: "Ali Draft", confirmation_token: "GRC-ALI")
      create(:guest_registration_card, :signed, booking: signed_booking, hotel: hotel)
      create(:guest_registration_card, booking: draft_booking, hotel: hotel)

      get guest_registration_cards_hotel_reports_path(hotel), params: { status: "signed", q: "Jane" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Jane GRC")
      expect(response.body).not_to include("Ali Draft")
      expect(response.body).to include("data-controller=\"auto-submit\"")
      expect(response.body).to include("data-turbo-frame=\"grc_results\"")
      expect(response.body).to include("input-&gt;auto-submit#submit")
      expect(response.body).not_to include("Filter")
    end

    it "searches by confirmation token case-insensitively" do
      matching_booking = create(:booking, hotel: hotel, guest_name: "Token Match", confirmation_token: "8TPT7Y")
      other_booking = create(:booking, hotel: hotel, guest_name: "Token Miss", confirmation_token: "HCXUNU")
      create(:guest_registration_card, booking: matching_booking, hotel: hotel)
      create(:guest_registration_card, booking: other_booking, hotel: hotel)

      get guest_registration_cards_hotel_reports_path(hotel), params: { q: "8tp" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Token Match")
      expect(response.body).not_to include("Token Miss")
    end

    it "searches by formatted guest registration card number" do
      booking = create(:booking, hotel: hotel, guest_name: "Formatted GRC", confirmation_token: "GRC-FMT")
      create(:guest_registration_card, booking: booking, hotel: hotel)

      get guest_registration_cards_hotel_reports_path(hotel), params: { q: booking.guest_registration_card_number_display.delete("-").downcase }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Formatted GRC")
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
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day, guest_name: "Occ Guest")
      create(:booking_room, booking: booking, room_type: room_type, quantity: 2, subtotal: 300)

      get daily_occupancy_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Daily Occupancy Report")
      expect(response.body).to include("Rooms Sold")
    end

    it "does not include data from another hotel" do
      room_type = create(:room_type, hotel: create(:hotel), quantity: 10)
      booking = create(:booking, hotel: room_type.hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day)
      create(:booking_room, booking: booking, room_type: room_type, quantity: 5, subtotal: 500)

      get daily_occupancy_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Daily Occupancy Report")
      expect(response.body).not_to include(booking.confirmation_token)
    end

    it "defaults blank first load to today" do
      travel_to(Time.zone.local(2026, 6, 15, 10, 0, 0)) do
        room_type = create(:room_type, hotel: hotel, quantity: 10)
        create(:room_inventory, room_type: room_type, date: Date.new(2026, 6, 1), quantity: 8, status: "open")
        create(:room_inventory, room_type: room_type, date: Date.new(2026, 6, 15), quantity: 9, status: "open")

        booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 6, 1), check_out: Date.new(2026, 6, 16), guest_name: "Month Guest")
        create(:booking_room, booking: booking, room_type: room_type, quantity: 2, subtotal: 300)

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
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day)
      create(:booking_room, booking: booking, room_type: room_type, quantity: 2, subtotal: 300)

      get daily_occupancy_hotel_reports_path(hotel, format: :csv), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Date,Rooms Sold,Rooms Available,Occupancy %,Room Revenue,Average Daily Rate (ADR),Revenue per Available Room (RevPAR)")
    end

    it "exports PDF" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day)
      create(:booking_room, booking: booking, room_type: room_type, quantity: 1, subtotal: 120)

      get daily_occupancy_hotel_reports_path(hotel, format: :pdf), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include(".pdf")
    end

    it "exports XLS" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day)
      create(:booking_room, booking: booking, room_type: room_type, quantity: 1, subtotal: 120)

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

  describe "GET /daily_revenue" do
    let(:start_date) { Date.new(2026, 5, 6) }
    let(:end_date) { Date.new(2026, 5, 7) }

    it "renders daily revenue report for selected range" do
      create(:booking, hotel: hotel, status: "confirmed", source: "walk_in", total_amount: 100, tourism_tax_applied: true, tourism_tax_amount: 10, created_at: Time.zone.local(2026, 5, 6, 10, 0))
      create(:booking, hotel: hotel, status: "completed", source: "agoda", total_amount: 200, created_at: Time.zone.local(2026, 5, 7, 11, 0))

      get daily_revenue_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Daily Revenue Report")
      expect(response.body).to include("Revenue by Source")
    end

    it "exports csv/xls/pdf" do
      create(:booking, hotel: hotel, status: "confirmed", source: "walk_in", total_amount: 100, created_at: Time.zone.local(2026, 5, 6, 10, 0))

      get daily_revenue_hotel_reports_path(hotel, format: :csv), params: { start_date: start_date.to_s, end_date: end_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")

      get daily_revenue_hotel_reports_path(hotel, format: :xls), params: { start_date: start_date.to_s, end_date: end_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")

      get daily_revenue_hotel_reports_path(hotel, format: :pdf), params: { start_date: start_date.to_s, end_date: end_date.to_s }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
    end

    it "requires view_reports permission" do
      role.permissions.delete(Permission.find_by!(slug: "view_reports"))

      get daily_revenue_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end
  end

  describe "GET /managers_flash" do
    let(:start_date) { Date.new(2026, 5, 6) }
    let(:end_date) { Date.new(2026, 5, 7) }

    it "renders the manager flash report for the selected range" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day)
      create(:booking_room, booking: booking, room_type: room_type, quantity: 2, subtotal: 400)

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
      expect(response.body).to include('data-tabs-default-tab-value="paid"')
      expect(response.body).to include('data-testid="payouts-upcoming-panel"')
      expect(response.body).to include('data-testid="payouts-paid-panel"')
      expect(response.body).to include("data-tabs-breadcrumb-label>Paid History</span>")
    end

    it "falls back to upcoming for an unknown tab" do
      get payouts_hotel_reports_path(hotel), params: { tab: "unknown" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-tabs-default-tab-value="upcoming"')
      expect(response.body).to include("data-tabs-breadcrumb-label>Upcoming &amp; Processing</span>")
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
      create(:booking_room, booking: booking, room_type: room_type, quantity: 1)
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
end
