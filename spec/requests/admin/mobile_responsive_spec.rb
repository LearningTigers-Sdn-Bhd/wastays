require 'rails_helper'
require 'securerandom'

RSpec.describe 'Admin mobile responsive views', type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:account) { create(:account, name: "Admin Mobile #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: account, email: "admin-mobile-#{token}@example.com") }

  before do
    sign_in_as(superadmin)
  end

  it 'renders the dashboard mobile bookings list container' do
    get admin_dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin-dashboard-mobile-bookings"')
  end

  it 'renders the hotels mobile list container' do
    get admin_hotels_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin-hotels-mobile-list"')
  end

  it 'uses consistent mobile page heading sizes across admin index pages' do
    {
      admin_dashboard_path => 'Dashboard',
      admin_hotels_path => 'Manage Hotels',
      admin_bookings_path => 'Platform Bookings',
      admin_reconciliations_path => 'Payment Issues',
      admin_margin_rules_path => 'Margin Settings',
      admin_audit_logs_path => 'Audit Logs'
    }.each do |path, heading|
      get path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(class="text-2xl font-bold tracking-tight text-slate-950 sm:text-3xl">#{heading}))
    end
  end

  it 'renders the bookings mobile list container' do
    get admin_bookings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin-bookings-mobile-list"')
  end

  it 'renders the payment issues mobile list container' do
    get admin_reconciliations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin-payment-issues-mobile-list"')
  end

  it 'renders the audit logs mobile list container' do
    get admin_audit_logs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin-audit-logs-mobile-list"')
  end

  it 'renders the margin rules mobile list container' do
    get admin_margin_rules_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin-margin-rules-mobile-list"')
  end

  it 'renders the analytics mobile list container' do
    get admin_analytics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin-analytics-mobile-list"')
  end
end
