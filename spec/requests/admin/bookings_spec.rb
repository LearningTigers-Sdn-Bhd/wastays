require 'rails_helper'
require 'securerandom'

RSpec.describe 'Admin::Bookings', type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin Bookings #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: admin_account, email: "admin-bookings-#{token}@example.com") }
  let(:hotel_account) { create(:account, name: "Kinabalu Rainforest Group #{token}") }
  let(:hotel) { create(:hotel, account: hotel_account, name: "Kinabalu Rainforest Lodge #{token}", city: 'Kota Kinabalu', country: 'Malaysia', status: 'approved') }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      booking_quote: create(:booking_quote, hotel: hotel, token: "tok_#{token}_booking"),
      confirmation_token: 'FBBP4A',
      guest_name: 'Tom Becker',
      guest_email: 'tom.becker@example.com',
      guest_phone: '+60192223344',
      total_amount: 520.0,
      check_in: Date.new(2026, 4, 10),
      check_out: Date.new(2026, 4, 12),
      hotel_snapshot: { room_number: "101" }
    )
  end

  let!(:booking_room) do
    create(:booking_room,
      booking: booking,
      room_type: create(:room_type, hotel: hotel, name: 'Deluxe Room')
    )
  end

  before do
    sign_in_as(superadmin)
  end

  def create_closed_folio_with_charge!(target_booking)
    folio = create(:booking_folio, booking: target_booking, hotel: target_booking.hotel, status: "closed", invoice_number: 123)
    code = create(:transaction_code, hotel: target_booking.hotel, code: "RM-ACC", name: "Room / Accommodation", kind: "charge", category: "accommodation")
    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: code,
      transaction_type: "charge",
      category: "accommodation",
      amount: 520,
      description: "Room Charge - Deluxe Room")
    folio
  end

  describe 'GET /admin/bookings/:id' do
    it 'renders the booking detail header with back link and summary description' do
      get admin_booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Back to All Bookings')
      expect(response.body).to include('class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl">Booking FBBP4A')
      expect(response.body).to include('class="mt-2 text-sm font-medium text-muted-foreground sm:text-base">Review booking details, guest information, and payment status for this reservation.')
      expect(response.body).to include('Review booking details, guest information, and payment status for this reservation.')
      expect(response.body).to include('class="text-lg font-bold tracking-tight text-foreground sm:text-xl">')
      expect(response.body).to include('Stay & Room Details')
      expect(response.body).to include('Room 101')
      expect(response.body).to include('class="mb-4 text-lg font-bold tracking-tight text-foreground sm:text-xl">Status Summary')
      expect(response.body).to include('Booking FBBP4A')
      expect(response.body).to include("Hotel: #{hotel.name}")
    end

    it 'renders the pre check-in status in the summary' do
      create(:pre_checkin, booking: booking, status: 'completed', completed_at: Time.current)

      get admin_booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Pre Check-In Status')
      expect(response.body).to include('Completed')
    end
  end

  describe 'GET /admin/bookings/:id/invoice' do
    it 'returns a PDF for a booking with a closed folio' do
      create_closed_folio_with_charge!(booking)

      get invoice_admin_booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("inline")
    end

    it 'redirects when the booking has no closed folio' do
      get invoice_admin_booking_path(booking)

      expect(response).to redirect_to(admin_booking_path(booking))
      expect(flash[:alert]).to eq("Invoice is only available after checkout.")
    end
  end
end
