# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::StaffPasswords", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:manager) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:staff) { create(:user, account: hotel.account, temporary_password: "password123", temporary_password_hotel: hotel) }
  let(:access) { create(:user_hotel_access, user: staff, hotel: hotel, role: role) }

  before do
    role.permissions << (Permission.find_by(slug: "manage_users") || create(:permission, slug: "manage_users"))
    create(:user_hotel_access, user: manager, hotel: hotel, role: role)
    sign_in_as(manager)
  end

  it "shows a single read-only copyable message in the non-cached settings sheet" do
    get hotel_user_temporary_password_path(hotel, access), headers: { "Turbo-Frame" => "settings_action_sheet" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    doc = response.parsed_body
    expect(doc.at_css('turbo-frame[ id="settings_action_sheet"]')).to be_present
    message = doc.at_css('textarea[data-clipboard-target="source"]')
    expect(message["readonly"]).to be_present
    expect(message.text).to include("1. Open #{login_url}", "Login email: #{staff.email}", "Temporary password: password123",
      "My Profile", "Change password", "current password")
    expect(doc.css('[data-clipboard-target="source"]').length).to eq(1)
    expect(doc.css('[data-action="clipboard#copy"]').length).to eq(1)
  end

  it "does not expose passwords in the directory but offers the eligible row action" do
    access
    get hotel_users_path(hotel)

    expect(response.body).to include("View temporary sign-in details", hotel_user_temporary_password_path(hotel, access))
    expect(response.body).not_to include("password123")
  end

  it "requires manage_users without exposing the password" do
    access
    role.permissions.clear
    get hotel_user_temporary_password_path(hotel, access)

    expect(response).to have_http_status(:redirect)
    expect(response.body).not_to include("password123")
  end

  it "rejects cross-property access IDs" do
    other = create(:user_hotel_access)
    get hotel_user_temporary_password_path(hotel, other)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects revoked access and hides the action" do
    access.deactivate!
    get hotel_user_temporary_password_path(hotel, access)
    expect(response).to have_http_status(:not_found)
    get hotel_users_path(hotel)
    expect(response.body).not_to include("View temporary sign-in details")
  end

  it "rejects passwords created at another property and hides the action" do
    staff.update!(temporary_password_hotel: create(:hotel, account: hotel.account))
    get hotel_user_temporary_password_path(hotel, access)
    expect(response).to have_http_status(:not_found)
    get hotel_users_path(hotel)
    expect(response.body).not_to include("View temporary sign-in details")
  end

  it "rejects passwords that no longer authenticate" do
    staff.update!(password: "personal-password", password_confirmation: "personal-password")
    get hotel_user_temporary_password_path(hotel, access)
    expect(response).to have_http_status(:not_found)
    get hotel_users_path(hotel)
    expect(response.body).not_to include("View temporary sign-in details")
  end

  it "clears credentials through My Profile and removes the manager's reveal action" do
    access
    sign_in_as(staff)
    patch hotel_user_profile_path(hotel), params: { user: { current_password: "password123",
      password: "personal-password", password_confirmation: "personal-password" } }
    expect(response).to redirect_to(edit_hotel_user_profile_path(hotel))
    expect(staff.reload.temporary_password).to be_nil

    sign_in_as(manager)
    get hotel_user_temporary_password_path(hotel, access)
    expect(response).to have_http_status(:not_found)
    get hotel_users_path(hotel)
    expect(response.body).not_to include("View temporary sign-in details")
  end
end
