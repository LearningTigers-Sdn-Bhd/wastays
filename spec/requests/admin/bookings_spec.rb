require 'rails_helper'

RSpec.describe 'Admin::Bookings', type: :request do
  let(:superadmin) { create(:user, :superadmin) }
  let(:hotel) { create(:hotel, name: 'Kinabalu Rainforest Lodge', city: 'Kota Kinabalu', country: 'Malaysia', status: 'approved') }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
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
      expect(response.body).to include('Review booking details, guest information, and payment status for this reservation.')
      expect(response.body).to include('Booking WS-FBBPGNAT')
      expect(response.body).to include('Hotel: Kinabalu Rainforest Lodge')
    end
  end
end
