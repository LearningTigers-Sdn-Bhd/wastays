require "rails_helper"

RSpec.describe "HotelPortal::CorporateAccountPasswords", type: :request do
  let(:hotel) { create(:hotel) }
  let(:staff) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:corporate_user) { create(:user, :corporate, temporary_password: "password123", temporary_password_hotel: hotel) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account) }

  before do
    role.permissions << (Permission.find_by(slug: "manage_corporate_accounts") || create(:permission, slug: "manage_corporate_accounts"))
    create(:user_hotel_access, user: staff, hotel: hotel, role: role)
    sign_in_as(staff)
  end

  it "reveals credentials in a non-cached sheet only on request" do
    get hotel_corporate_account_temporary_password_path(hotel, relationship), headers: { "Turbo-Frame" => "external_account_sheet" }
    expect(response).to have_http_status(:success)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body).to include(corporate_user.email, "password123", "external_account_sheet")
    document = response.parsed_body
    message = document.at_css('textarea[data-clipboard-target="source"]')
    expect(message["readonly"]).to be_present
    expect(message.text).to include("1. Open #{login_url}", "2. Sign in", "Login email: #{corporate_user.email}",
      "Temporary password: password123", "3. Open Profile", "Change password")
    expect(document.css('[data-clipboard-target="source"]').length).to eq(1)
    expect(document.css('[data-action="clipboard#copy"]').length).to eq(1)
  end

  it "rejects cross-hotel relationships and passwords created elsewhere" do
    other_relationship = create(:hotel_corporate_account, corporate_account: corporate_user.account)
    get hotel_corporate_account_temporary_password_path(hotel, other_relationship)
    expect(response).to have_http_status(:not_found)
    corporate_user.update!(temporary_password_hotel: other_relationship.hotel)
    get hotel_corporate_account_temporary_password_path(hotel, relationship)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects reveals after a password change" do
    Users::UpdateProfile.call(user: corporate_user, params: { current_password: "password123", password: "personal-password", password_confirmation: "personal-password" })
    get hotel_corporate_account_temporary_password_path(hotel, relationship)
    expect(response).to have_http_status(:not_found)
  end

  it "requires account-management permission" do
    relationship
    role.permissions.clear
    get hotel_corporate_account_temporary_password_path(hotel, relationship)
    expect(response).to have_http_status(:redirect)
    expect(response.body).not_to include("password123")
  end
end
