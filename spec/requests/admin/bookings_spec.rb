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
      confirmation_token: 'WS-FBBPGNAT',
      guest_name: 'Tom Becker',
      guest_email: 'tom.becker@example.com',
      guest_phone: '+60192223344',
      total_amount: 520.0,
      check_in: Date.new(2026, 4, 10),
      check_out: Date.new(2026, 4, 12)
    )
  end

  before do
    sign_in_as(superadmin)
  end

  describe 'GET /admin/bookings/:id' do
    it 'renders the booking detail header with back link and summary description' do
      get admin_booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Back to All Bookings')
      expect(response.body).to include('class="text-2xl font-bold tracking-tight text-slate-950 sm:text-3xl">Booking WS-FBBPGNAT')
      expect(response.body).to include('class="mt-2 text-sm font-medium text-slate-600 sm:text-base">Review booking details, guest information, and payment status for this reservation.')
      expect(response.body).to include('Review booking details, guest information, and payment status for this reservation.')
      expect(response.body).to include('class="text-lg font-bold tracking-tight text-slate-950 sm:text-xl">')
      expect(response.body).to include('Stay & Room Details')
      expect(response.body).to include('class="mb-4 text-lg font-bold tracking-tight text-slate-950 sm:text-xl">Status Summary')
      expect(response.body).to include('Booking WS-FBBPGNAT')
      expect(response.body).to include("Hotel: #{hotel.name}")
    end
  end
end
