require "rails_helper"

RSpec.describe "Hotel portal global search", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    Permission.find_or_create_by!(slug: "manage_account") { |permission| permission.name = "Manage Account" }
    Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: "manage_account"))
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: "manage_hotel_profile"))
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "returns hotel pages beyond the original sidebar set" do
    get hotel_global_search_index_path(hotel), params: { q: "archive" }, headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    archive_titles = JSON.parse(response.body).fetch("results").map { |row| row.fetch("title") }
    expect(archive_titles).to include("Request Archive")

    get hotel_global_search_index_path(hotel), params: { q: "profile" }, headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    profile_titles = JSON.parse(response.body).fetch("results").map { |row| row.fetch("title") }
    expect(profile_titles).to include("Hotel Details", "My Profile")
  end

  it "returns support destinations" do
    get hotel_global_search_index_path(hotel), params: { q: "help" }, headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    titles = JSON.parse(response.body).fetch("results").map { |row| row.fetch("title") }

    expect(titles).to include("Help & Support")
  end

  it "returns room readiness destination" do
    get hotel_global_search_index_path(hotel), params: { q: "room readiness" }, headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    titles = JSON.parse(response.body).fetch("results").map { |row| row.fetch("title") }

    expect(titles).to include("Room Readiness")
  end
end
