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

  # The hotels index no longer ships a separate mobile list: the registry is one
  # responsive table that folds columns away and surfaces the city inline on
  # small screens. Assert that folding instead of the retired container id.
  it 'renders the hotels registry with columns that fold away on mobile' do
    create(:hotel, account: account)

    get admin_hotels_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="hotels_list"')
    expect(response.body).to include('hidden sm:table-cell')
    expect(response.body).to include('sm:hidden')
  end

  it 'uses consistent mobile page heading sizes across admin index pages' do
    {
      admin_dashboard_path => 'Dashboard',
      admin_hotels_path => 'Manage Hotels',
      admin_bookings_path => 'Platform Bookings',
      admin_reconciliations_path => 'Payment Issues',
      admin_margin_rules_path => 'Margin Settings',
      admin_setup_fee_rules_path => 'Setup Fee Settings',
      admin_audit_logs_path => 'Audit Logs'
    }.each do |path, heading|
      get path

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("header.panel-page-header h1").text).to eq(heading)
    end
  end

  it 'renders the api access page with the shared admin index shell' do
    get admin_api_keys_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('class="w-full space-y-8"')
    expect(Nokogiri::HTML(response.body).at_css("header.panel-page-header h1").text).to eq("API Access Management")
    expect(response.body).to include('Manage programmatic access for chatbots and external integrations.')
  end

  it 'renders the new api access key page with the shared admin form shell' do
    get new_admin_api_key_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('class="w-full space-y-6"')
    expect(response.body).to include('Create API Access Key')
    expect(response.body).to include('Generate a credential for platform-wide or restricted integration access.')
    expect(response.body).to include('mt-auto flex flex-col gap-3 border-t border-border pt-6 sm:flex-row sm:items-center sm:justify-end')
  end

  it 'renders the developer guide with the shared admin documentation shell' do
    get docs_admin_api_keys_path(category: 'authentication')

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('class="w-full space-y-8"')
    expect(response.body).to include('API Integration Guide')
    expect(response.body).to include('Build against WAStays endpoints with authentication, discovery, booking, and webhook references.')
    expect(response.body).to include('Copy Base URL')
  end

  it 'renders the developer navigation links in the shared sidebar' do
    get admin_dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(href="#{admin_api_keys_path}"))
    expect(response.body).to include(%(href="#{docs_admin_api_keys_path}"))
    expect(response.body).to include(%(href="#{admin_setup_fee_rules_path}"))
    expect(response.body).to include('API Access')
    expect(response.body).to include('Developer Guide')
    expect(response.body).to include('Setup Fee Settings')
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

  it 'renders the setup fee rules mobile list container' do
    get admin_setup_fee_rules_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin-setup-fee-rules-mobile-list"')
    expect(response.body).to include('Setup Fee Settings')
    expect(response.body).to include('Add New Rule')
  end

  it 'renders the analytics mobile list container' do
    get admin_analytics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin-analytics-mobile-list"')
  end

  it 'renders the analytics page with the shared admin index shell' do
    get admin_analytics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('class="w-full space-y-8"')
    expect(Nokogiri::HTML(response.body).at_css("header.panel-page-header h1").text).to eq("Revenue & Margin Analytics")
  end

  it 'renders analytics filters inside the daily breakdown section' do
    get admin_analytics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin-analytics-filters"')
    expect(response.body).to include('id="admin-analytics-filters-toolbar"')
  end
end
