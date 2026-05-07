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
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, guest_name: "Unpaid Guest", confirmation_token: "WS-UNPAID")
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", check_in: start_date, check_out: start_date + 1.day, guest_name: "Paid Guest", confirmation_token: "WS-PAID")

      get outstanding_balance_hotel_reports_path(hotel), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Outstanding Balance Report")
      expect(response.body).to include("Unpaid Guest")
      expect(response.body).not_to include("Paid Guest")
    end

    it "exports CSV" do
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, guest_name: "CSV Outstanding", confirmation_token: "WS-OB-CSV")

      get outstanding_balance_hotel_reports_path(hotel, format: :csv), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Guest Name,Booking Ref,Stay,Rooms,Room Numbers,Payment Status,Outstanding Amount,Notes")
      expect(response.body).to include("CSV Outstanding")
    end

    it "exports PDF" do
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day)

      get outstanding_balance_hotel_reports_path(hotel, format: :pdf), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include(".pdf")
    end

    it "exports XLS" do
      create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, guest_name: "Excel Outstanding")

      get outstanding_balance_hotel_reports_path(hotel, format: :xls), params: { start_date: start_date.to_s, end_date: end_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/vnd.ms-excel")
      expect(response.headers["Content-Disposition"]).to include(".xls")
      expect(response.body).to include('ss:Name="Summary"')
      expect(response.body).to include('ss:Name="Outstanding Balances"')
    end
  end
end
