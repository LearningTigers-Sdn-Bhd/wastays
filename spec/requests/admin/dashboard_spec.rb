require 'rails_helper'
require 'securerandom'

RSpec.describe 'Admin::Dashboard', type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin Dashboard #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: admin_account, email: "admin-dashboard-#{token}@example.com") }

  before do
    sign_in_as(superadmin)
  end

  describe 'GET /admin/dashboard' do
    it 'renders the current dashboard overview and bookings entry point' do
      get admin_dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('class="text-2xl font-bold tracking-tight text-slate-950 sm:text-3xl">Dashboard')
      expect(response.body).to include('Platform overview and real-time operational status.')
      expect(response.body).to include('class="text-lg font-bold tracking-tight text-slate-950 sm:text-xl">Recent Successful Bookings')
      expect(response.body).to include('Recent Successful Bookings')
      expect(response.body).to include('View All Bookings')
      expect(response.body).to include('Payment Issues')
      expect(response.body).to include(admin_bookings_path)
      expect(response.body).to include(admin_reconciliation_dashboard_path)
    end

    it 'shows the created date for recent bookings' do
      hotel_account = create(:account, name: "Recent Booking Account #{token}", status: 'active')
      hotel = create(:hotel, account: hotel_account, name: "Recent Booking Hotel #{token}", status: 'approved')
      created_at = Time.zone.local(2021, 1, 7, 14, 30)

      create(
        :booking,
        hotel: hotel,
        booking_quote: create(:booking_quote, hotel: hotel, token: "recent_#{token}"),
        status: 'confirmed',
        total_amount: 300.0,
        check_in: Date.new(2026, 4, 15),
        check_out: Date.new(2026, 4, 17),
        created_at: created_at
      )

      get admin_dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Created Date')
      expect(response.body).to include(created_at.strftime('%d %b %Y'))
    end
  end

  describe 'GET /admin/analytics' do
    let(:account) { create(:account, name: "Luma Hospitality Group #{token}", status: 'active') }
    let(:hotel) { create(:hotel, account: account, name: "Luma Stay #{token}", status: 'approved') }
    let(:other_hotel_account) { create(:account, name: "Ocean Breeze Group #{token}", status: 'active') }
    let(:other_hotel) { create(:hotel, account: other_hotel_account, name: "Ocean Breeze #{token}", status: 'approved') }

    let!(:first_current_month_booking) do
      booking = create(
        :booking,
        hotel: hotel,
        booking_quote: create(:booking_quote, hotel: hotel, token: "tok_#{token}_1"),
        status: 'confirmed',
        total_amount: 500.0,
        margin_amount: 50.0,
        net_amount: 450.0,
        margin_rate: 10.0,
        created_at: Time.current.beginning_of_month + 2.days
      )
      folio = create(:booking_folio, hotel: hotel, booking: booking)
      create(:folio_transaction, booking_folio: folio, transaction_type: 'charge', category: 'accommodation', amount: 500.0, created_at: booking.created_at)
      booking
    end

    let!(:second_current_month_booking) do
      booking = create(
        :booking,
        hotel: other_hotel,
        booking_quote: create(:booking_quote, hotel: other_hotel, token: "tok_#{token}_2"),
        status: 'completed',
        total_amount: 300.0,
        margin_amount: 45.0,
        net_amount: 255.0,
        margin_rate: 15.0,
        created_at: Time.current.beginning_of_month + 5.days
      )
      folio = create(:booking_folio, hotel: other_hotel, booking: booking)
      create(:folio_transaction, booking_folio: folio, transaction_type: 'charge', category: 'accommodation', amount: 300.0, created_at: booking.created_at)
      booking
    end


    let!(:previous_month_booking) do
      create(
        :booking,
        hotel: hotel,
        booking_quote: create(:booking_quote, hotel: hotel, token: "tok_#{token}_3"),
        status: 'confirmed',
        total_amount: 900.0,
        margin_amount: 90.0,
        net_amount: 810.0,
        margin_rate: 10.0,
        created_at: 1.month.ago.beginning_of_month + 1.day
      )
    end

    it 'shows global current-month analytics across hotels' do
      get admin_analytics_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('class="text-2xl font-bold tracking-tight text-slate-950 sm:text-3xl">Revenue &amp; Margin Analytics')
      expect(response.body).to include('Revenue &amp; Margin Analytics')
      expect(response.body).to include('Detailed superadmin analytics across all revenue-generating bookings.')
      expect(response.body).to include('class="text-lg font-bold tracking-tight text-slate-950 sm:text-xl">Daily Breakdown')
      expect(response.body).to include('RM 800.00')
      expect(response.body).to include('RM 95.00')
      expect(response.body).to include('RM 705.00')
      expect(response.body).to include((Time.current.beginning_of_month + 2.days).strftime('%d %b %Y'))
      expect(response.body).to include((Time.current.beginning_of_month + 5.days).strftime('%d %b %Y'))
      expect(response.body).not_to include((1.month.ago.beginning_of_month + 1.day).strftime('%d %b %Y'))
    end

    it 'filters analytics by the selected date range' do
      selected_date = (Time.current.beginning_of_month + 5.days).to_date

      get admin_analytics_path, params: { date_preset: "custom", start_date: selected_date, end_date: selected_date }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('RM 300.00')
      expect(response.body).to include('RM 45.00')
      expect(response.body).to include('RM 255.00')
      expect(response.body).to include(selected_date.strftime('%d %b %Y'))
      expect(response.body).not_to include((Time.current.beginning_of_month + 2.days).strftime('%d %b %Y'))
      expect(response.body).not_to include('RM 500.00')
    end

    it 'shows the empty state when the date range has no analytics data' do
      future_start = Date.current.next_month.beginning_of_month
      future_end = Date.current.next_month.end_of_month

      get admin_analytics_path, params: { date_preset: "custom", start_date: future_start, end_date: future_end }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('No analytics data found.')
      expect(response.body).to include('Try adjusting the selected date range.')
    end
  end
end
