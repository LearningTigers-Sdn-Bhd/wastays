# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::Dashboard", type: :request do
  let(:user) { create(:user, :corporate) }

  before { sign_in_as(user) }

  it "routes corporate logins to the corporate dashboard" do
    delete logout_path

    post login_path, params: { email: user.email, password: user.password }

    expect(response).to redirect_to(corporate_dashboard_path)
  end

  it "shows only active linked hotels" do
    active_relationship = create(:hotel_corporate_account, corporate_account: user.account)
    suspended_relationship = create(:hotel_corporate_account, corporate_account: user.account, status: "suspended", suspended_at: Time.current)
    unrelated_relationship = create(:hotel_corporate_account)

    get corporate_dashboard_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(CGI.escapeHTML(active_relationship.hotel.name))
    expect(response.body).not_to include(CGI.escapeHTML(suspended_relationship.hotel.name))
    expect(response.body).not_to include(CGI.escapeHTML(unrelated_relationship.hotel.name))
  end

  it "renders the corporate sidebar, breadcrumb, and profile shell" do
    get corporate_dashboard_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include('id="corporate-sidebar"')
    expect(response.body).to include('aria-label="Corporate account:')
    expect(response.body).to include(CGI.escapeHTML(user.account.name))
    expect(response.body).to include('class="panel-sidebar__link"')
    expect(response.body).to include('aria-current="page"')
    expect(response.body).to include("Home")
    expect(response.body).to include("Dashboard")
    expect(response.body).to include(CGI.escapeHTML(user.email))
    expect(response.body).to include("Sign out")
    expect(response.body).to include('class="panel-navbar"')
    expect(response.body).to include('id="corporate-profile"')
    expect(response.body).to include('commandfor="corporate-sidebar-mobile"')
    expect(response.body).to include("Profile")
    expect(response.body).to include("AR Invoices")
    expect(response.body).to include("Payments")
  end

  it "shows outstanding balance for linked corporate invoices" do
    relationship = create(:hotel_corporate_account, corporate_account: user.account, credit_currency: "MYR")
    create_ar_invoice_for(relationship: relationship, amount: 125)

    get corporate_dashboard_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Outstanding balance")
    expect(response.body).to include("MYR 125.00")
  end

  it "rejects hotel users from the corporate portal" do
    hotel = create(:hotel)
    hotel_user = create(:user, account: hotel.account)
    create(:user_hotel_access, user: hotel_user, hotel: hotel)
    delete logout_path
    sign_in_as(hotel_user)

    get corporate_dashboard_path

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("not authorized")
  end

  it "redirects corporate users away from the hotel portal" do
    hotel = create(:hotel)

    get hotel_dashboard_path(hotel)

    expect(response).to redirect_to(corporate_dashboard_path)
  end

  it "blocks a suspended corporate account" do
    user.account.update!(status: "suspended")

    get corporate_dashboard_path

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to include("suspended")
  end

  def create_ar_invoice_for(relationship:, amount:)
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, outstanding_amount: amount, currency: "MYR")
  end
end
