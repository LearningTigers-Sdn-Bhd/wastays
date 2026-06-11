# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ReservationBoard::BoardBookings", type: :request do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101" ]) }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def sign_in_with_permissions(*slugs)
    user = create(:user)
    role = create(:role, account: hotel.account)
    slugs.each { |slug| grant_permission(role, slug) }
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/reservation-board/bookings/new" do
    it "responds successfully and pre-fills dates and room" do
      sign_in_with_permissions("manage_bookings")
      check_in = Date.current + 5.days

      get new_hotel_reservation_board_board_booking_path(hotel), params: {
        check_in: check_in.to_s,
        room_type_id: room_type.id,
        room_number: "101"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(check_in.to_s)
      expect(response.body).to include("101")
      expect(response.body).to include("New Booking")
    end
  end

  describe "POST /hotel/:hotel_id/reservation-board/bookings" do
    it "creates a booking and redirects to reservation board" do
      sign_in_with_permissions("manage_bookings")
      create(:room_rate, room_type: room_type, date: Date.current, price: 100, currency: hotel.default_currency.presence || "MYR")

      booking_params = {
        guest_name: "Board Guest",
        guest_email: "board@example.com",
        guest_phone: "12345678",
        check_in: Date.current.to_s,
        check_out: (Date.current + 1.day).to_s,
        room_type_id: room_type.id,
        room_number: "101",
        adults: 2,
        total_amount: 100
      }

      post hotel_reservation_board_board_bookings_path(hotel), params: { booking: booking_params }

      expect(response).to redirect_to(hotel_reservation_board_index_path(hotel))
      expect(hotel.bookings.last.guest_name).to eq("Board Guest")
    end

    it "persists the shared manual booking fields" do
      sign_in_with_permissions("manage_bookings")
      create(:room_rate, room_type: room_type, date: Date.current, price: 100, currency: hotel.default_currency.presence || "MYR")

      booking_params = {
        guest_name: "Board Guest",
        guest_email: "board@example.com",
        guest_phone: "+60123456789",
        guest_country: "Singapore",
        guest_gender: "female",
        guest_document_type: "passport",
        guest_government_id: "A12345678",
        check_in: Date.current.to_s,
        check_out: (Date.current + 1.day).to_s,
        room_type_id: room_type.id,
        room_number: "101",
        adults: 2,
        children: 1,
        source: "whatsapp",
        internal_notes: "Late arrival",
        manual_rate_override: "150.00",
        record_payment: "1",
        payment_method: "cash",
        payment_amount: "50.00",
        payment_reference: "RCPT-BOARD-1",
        apply_stop_sell_restriction: "1",
        apply_arrival_departure_restrictions: "1",
        apply_stay_length_restrictions: "1"
      }

      expect {
        post hotel_reservation_board_board_bookings_path(hotel), params: { booking: booking_params }
      }.to change(Booking, :count).by(1)
        .and change(PaymentTransaction, :count).by(1)

      booking = hotel.bookings.order(:created_at).last
      transaction = booking.payment_transactions.last

      expect(response).to redirect_to(hotel_reservation_board_index_path(hotel))
      expect(booking).to have_attributes(
        guest_name: "Board Guest",
        guest_email: "board@example.com",
        guest_phone: "+60123456789",
        guest_country: "Singapore",
        guest_gender: "female",
        source: "whatsapp",
        internal_notes: "Late arrival",
        manual_rate_override: 150.0,
        total_amount: 150.0,
        payment_status: "partial"
      )
      expect(booking.primary_guest).to have_attributes(
        country: "Singapore",
        gender: "female",
        document_type: "passport",
        government_id: "a12345678"
      )
      expect(transaction).to have_attributes(
        gateway: "manual",
        payment_method: "cash",
        amount_subunits: 5_000,
        external_reference: "RCPT-BOARD-1"
      )
    end
  end

  describe "GET /hotel/:hotel_id/reservation-board/bookings/:id" do
    let(:booking) { create(:booking, hotel: hotel) }

    it "responds successfully with board-specific modal content" do
      sign_in_with_permissions("manage_bookings")

      get hotel_reservation_board_board_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Booking")
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).to include("Operations")
      expect(response.body).to include(%(href="#{hotel_reservation_board_index_path(hotel)}">Reservation Board</a>))
    end
  end

  describe "GET /hotel/:hotel_id/reservation-board/bookings/:id/folio" do
    let(:booking) { create(:booking, hotel: hotel, check_out: Date.current + 2.days) }

    it "renders the shared compact folio page" do
      sign_in_with_permissions("manage_bookings", "post_folio_payments")
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, amount: 100)
      create(:folio_forecasted_charge, booking_folio: folio, stay_date: Date.current + 1.day, amount: 50)

      get folio_hotel_reservation_board_board_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Folio #{booking.confirmation_token}")
      expect(response.body).to include("Back to Booking")
      expect(response.body).to include("Operations")
      expect(response.body).to include(%(href="#{hotel_reservation_board_index_path(hotel)}">Reservation Board</a>))
      expect(response.body).to include(%(href="#{hotel_reservation_board_board_booking_path(hotel, booking)}"))
      expect(response.body).to include("Folio Ledger")
      expect(response.body).to include("Transaction Ledger")
      expect(response.body).to include("Posted Transactions")
      expect(response.body).to include("Upcoming / Forecasted Charges")
      expect(response.body).to include("Add Payment")
      expect(response.body).to include(hotel_reservation_board_board_booking_path(hotel, booking))
    end
  end

  describe "PATCH /hotel/:hotel_id/bookings/:id" do
    let(:booking) { create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 1.day) }

    before do
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    end

    it "responds with JSON for AJAX extensions" do
      sign_in_with_permissions("manage_bookings")
      new_check_out = Date.current + 2.days

      patch hotel_booking_path(hotel, booking),
            params: { booking: { check_out: new_check_out.to_s } },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["success"]).to be(true)
      expect(booking.reload.check_out).to eq(new_check_out)
    end
  end

  describe "PATCH /hotel/:hotel_id/reservation-board/bookings/:id/transition" do
    let(:booking) { create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current, check_out: Date.current + 2.days) }

    before do
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    end

    it "transitions booking to checked_in and returns turbo stream" do
      sign_in_with_permissions("manage_bookings", "manage_guest_arrival", "manage_room_status")

      patch transition_hotel_reservation_board_board_booking_path(hotel, booking),
            params: { status: "checked_in" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="reload"')
      expect(booking.reload.status).to eq("checked_in")
    end
  end
end
