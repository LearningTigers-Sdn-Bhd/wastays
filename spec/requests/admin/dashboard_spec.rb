require 'rails_helper'

RSpec.describe 'Admin::Dashboard', type: :request do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    sign_in_as(superadmin)
  end

  describe 'GET /admin/dashboard' do
    it 'renders the current dashboard overview and bookings entry point' do
      get admin_dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Platform overview and real-time operational status.')
      expect(response.body).to include('Recent Successful Bookings')
      expect(response.body).to include('View All Bookings')
      expect(response.body).to include('Payment Issues')
      expect(response.body).to include(admin_bookings_path)
      expect(response.body).to include(admin_reconciliation_dashboard_path)
    end
  end

  describe 'GET /admin/analytics' do
    let(:account) { create(:account, name: 'Luma Hospitality Group', status: 'active') }
    let(:hotel) { create(:hotel, account: account, name: 'Luma Stay', status: 'approved') }
    let(:other_hotel) { create(:hotel, name: 'Ocean Breeze', status: 'approved') }

    let!(:current_month_booking) do
      create(
        :booking,
        hotel: hotel,
        status: 'confirmed',
        total_amount: 500.0,
        margin_amount: 50.0,
        net_amount: 450.0,
        margin_rate: 10.0,
        created_at: Time.current.beginning_of_month + 2.days
      )
    end

    let!(:second_current_month_booking) do
      create(
        :booking,
        hotel: other_hotel,
        status: 'completed',
        total_amount: 300.0,
        margin_amount: 45.0,
        net_amount: 255.0,
        margin_rate: 15.0,
        created_at: Time.current.beginning_of_month + 5.days
      )
    end

    let!(:previous_month_booking) do
      create(
        :booking,
        hotel: hotel,
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
      expect(response.body).to include('Revenue & Margin Analytics')
      expect(response.body).to include('Detailed superadmin analytics across all revenue-generating bookings.')
      expect(response.body).to include('RM 800.00')
      expect(response.body).to include('RM 95.00')
      expect(response.body).to include('RM 705.00')
      expect(response.body).to include((Time.current.beginning_of_month + 2.days).strftime('%d %b %Y'))
      expect(response.body).to include((Time.current.beginning_of_month + 5.days).strftime('%d %b %Y'))
      expect(response.body).not_to include((1.month.ago.beginning_of_month + 1.day).strftime('%d %b %Y'))
    end

    it 'filters analytics by the selected date range' do
      selected_date = (Time.current.beginning_of_month + 5.days).to_date

      get admin_analytics_path, params: { start_date: selected_date, end_date: selected_date }

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

      get admin_analytics_path, params: { start_date: future_start, end_date: future_end }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('No analytics data found for this date range.')
    end
  end
end
