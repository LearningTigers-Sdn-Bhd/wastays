# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin panel access", type: :request do
  let(:account) { create(:account, name: "Admin Panel Access") }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let(:hotel_role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  let(:admin) { create(:user, :admin, account: account) }

  it "redirects superadmins to the admin dashboard after login" do
    superadmin = create(:user, :superadmin, account: account)

    sign_in_as(superadmin)

    expect(response).to redirect_to(admin_dashboard_path)
  end

  it "redirects hotel admins to the hotel dashboard after login" do
    admin = create(:user, :admin, account: account)
    UserHotelAccess.create!(user: admin, hotel: hotel, role: hotel_role)

    sign_in_as(admin)

    expect(response).to redirect_to(hotel_dashboard_path(hotel))
  end

  it "does not allow hotel admins to access the admin dashboard" do
    get admin_dashboard_path
    UserHotelAccess.create!(user: admin, hotel: hotel, role: hotel_role)
    sign_in_as(admin)
    get admin_dashboard_path

    expect(response).to redirect_to(root_path)
  end

  it "does not allow hotel staff to access the admin dashboard" do
    hotel_staff = create(:user, account: account)

    get admin_dashboard_path
    sign_in_as(hotel_staff)
    get admin_dashboard_path

    expect(response).to redirect_to(root_path)
  end

  it "keeps Observation Deck restricted to superadmins" do
    get admin_observation_deck_index_path
    UserHotelAccess.create!(user: admin, hotel: hotel, role: hotel_role)
    sign_in_as(admin)
    get admin_observation_deck_index_path

    expect(response).to have_http_status(:not_found)
  end
end
