# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin panel access", type: :request do
  let(:account) { create(:account, name: "Admin Panel Access") }

  it "redirects admins to the admin dashboard after login" do
    admin = create(:user, :admin, account: account)

    sign_in_as(admin)

    expect(response).to redirect_to(admin_dashboard_path)
  end

  it "allows admins to access the admin dashboard" do
    admin = create(:user, :admin, account: account)

    get admin_dashboard_path
    sign_in_as(admin)
    get admin_dashboard_path

    expect(response).to have_http_status(:ok)
  end

  it "does not allow hotel staff to access the admin dashboard" do
    hotel_staff = create(:user, account: account)

    get admin_dashboard_path
    sign_in_as(hotel_staff)
    get admin_dashboard_path

    expect(response).to redirect_to(root_path)
  end

  it "keeps Observation Deck restricted to superadmins" do
    admin = create(:user, :admin, account: account)

    get admin_observation_deck_index_path
    sign_in_as(admin)
    get admin_observation_deck_index_path

    expect(response).to have_http_status(:not_found)
  end
end
