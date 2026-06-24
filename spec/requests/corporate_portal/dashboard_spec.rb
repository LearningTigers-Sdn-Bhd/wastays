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
end
