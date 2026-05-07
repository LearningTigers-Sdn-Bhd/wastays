require 'rails_helper'

RSpec.describe "HotelPortal::Reports", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "returns http success" do
      get "/hotel/#{hotel.id}/reports"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /arrivals_departures" do
    let(:start_date) { Date.new(2026, 5, 7) }
    let(:end_date) { Date.new(2026, 5, 8) }

    it "renders the arrivals and departures report for the selected date range" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Arriving Guest", confirmation_token: "WS-ARR")
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: start_date, guest_name: "Departing Guest", confirmation_token: "WS-DEP")
      create(:booking, hotel: hotel, status: "confirmed", check_in: end_date + 1.day, check_out: end_date + 2.days, guest_name: "Wrong Date")

      get arrivals_departures_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Arrivals &amp; Departures")
      expect(response.body).to include("Arriving Guest")
      expect(response.body).to include("Departing Guest")
      expect(response.body).not_to include("Wrong Date")
    end

    it "does not show bookings from another hotel" do
      create(:booking, hotel: create(:hotel), status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Other Hotel Guest")

      get arrivals_departures_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Other Hotel Guest")
    end

    it "falls back to today when both start and end dates are invalid" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current, check_out: Date.current + 1.day, guest_name: "Today Guest")

      get arrivals_departures_hotel_reports_path(hotel), params: { start_date: "bad-start", end_date: "bad-end" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Today Guest")
    end

    it "supports single-date legacy param for backward compatibility" do
      date = Date.new(2026, 5, 10)
      create(:booking, hotel: hotel, status: "confirmed", check_in: date, check_out: date + 1.day, guest_name: "Legacy Date Guest")

      get arrivals_departures_hotel_reports_path(hotel), params: { date: date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Legacy Date Guest")
    end

    it "aligns end date to start date when start date is later than end date" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 10), check_out: Date.new(2026, 5, 11), guest_name: "Start Date Guest")
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 8), check_out: Date.new(2026, 5, 9), guest_name: "Old Date Guest")

      get arrivals_departures_hotel_reports_path(hotel), params: {
        start_date: "2026-05-10",
        end_date: "2026-05-09"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Start Date Guest")
      expect(response.body).not_to include("Old Date Guest")
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

    it "exports Excel with separate arrival and departure worksheets" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Excel Guest", confirmation_token: "WS-XLS")

      get arrivals_departures_hotel_reports_path(hotel, format: :xls), params: {
        start_date: start_date.to_s,
        end_date: end_date.to_s
      }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")
      expect(response.headers["Content-Disposition"]).to include(".xls")
      expect(response.body).to include('ss:Name="Arrivals"')
      expect(response.body).to include('ss:Name="Departures"')
      expect(response.body).to include("Excel Guest")
    end
  end
end
