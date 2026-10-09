require "rails_helper"

RSpec.describe "HotelPortal::CorporateAccountWorkspace", type: :request do
  let(:hotel) { create(:hotel) }
  let(:staff) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:corporate_user) { create(:user, :corporate) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account) }

  before do
    role.permissions << (Permission.find_by(slug: "manage_corporate_accounts") || create(:permission, slug: "manage_corporate_accounts"))
    create(:user_hotel_access, user: staff, hotel: hotel, role: role)
    sign_in_as(staff)
  end

  it "opens a full-height workspace with the saved relationship selected and three URL-backed tabs" do
    get edit_hotel_corporate_account_path(hotel, relationship)
    expect(response.body).to include("panel-page--full-height", "Manage billing", "Company details", "Billing address")
    expect(response.parsed_body.at_css('input[type="radio"][value="standard"]')["checked"]).to be_present
    expect(response.body).not_to include('dialog id="external-account-sheet"')
    expect(response.parsed_body.css('#corporate-account-tabs a').length).to eq(3)
  end

  it "loads only the selected tab into the workspace frame" do
    get edit_hotel_corporate_account_path(hotel, relationship, tab: "company_details"), headers: { "Turbo-Frame" => "corporate_account_workspace" }
    expect(response.parsed_body.at_css('turbo-frame#corporate_account_workspace')).to be_present
    expect(response.body).to include("Company name", "Contact person", "Login email")
    expect(response.body).not_to include("Credit limit", "Address line 1", "<!DOCTYPE")
    expect(response.parsed_body.at_css('input[name="hotel_corporate_account[corporate_account][name]"]')).to be_present
    expect(response.parsed_body.at_css('input[name="hotel_corporate_account[corporate_user][email]"]')).to be_present
  end

  it "saves shared company details and returns to the same tab" do
    digest = corporate_user.password_digest
    patch hotel_corporate_account_path(hotel, relationship), params: { tab: "company_details", hotel_corporate_account: {
      corporate_account: { name: "Updated Agency" }, corporate_user: { name: "Updated Contact", email: "updated@example.com", password: "ignored" }, contact_phone: "123"
    } }
    expect(response).to redirect_to(edit_hotel_corporate_account_path(hotel, relationship, tab: "company_details", return_to: hotel_corporate_accounts_path(hotel)))
    expect(corporate_user.reload).to have_attributes(name: "Updated Contact", email: "updated@example.com", password_digest: digest)
    expect(relationship.reload.corporate_account.name).to eq("Updated Agency")
    follow_redirect!
    expect(response.body).to include("Updated Agency")
  end

  it "keeps submitted fields and shows validation errors on the same tab" do
    taken = create(:user)
    patch hotel_corporate_account_path(hotel, relationship), params: { tab: "company_details", hotel_corporate_account: {
      corporate_account: { name: "Typed Agency" }, corporate_user: { email: taken.email }
    } }, headers: { "Turbo-Frame" => "corporate_account_workspace" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Typed Agency", "has already been taken")
    expect(response.parsed_body.at_css('input[name="tab"]')["value"]).to eq("company_details")
  end

  it "edits billing address without submitting company fields" do
    get edit_hotel_corporate_account_path(hotel, relationship, tab: "billing_address")
    expect(response.body).to include("Address line 1", "Billing address missing")
    expect(response.body).not_to include("Company name", "Credit limit")
    patch hotel_corporate_account_path(hotel, relationship), params: { tab: "billing_address", hotel_corporate_account: { billing_city: "Kota Kinabalu" } }
    expect(relationship.reload.billing_city).to eq("Kota Kinabalu")
    expect(response.location).to include("tab=billing_address")
  end

  it "offers Invite contact for unclaimed accounts without login fields" do
    unclaimed = create(:hotel_corporate_account, hotel: hotel)
    get edit_hotel_corporate_account_path(hotel, unclaimed, tab: "company_details")
    expect(response.body).to include("Invite contact", "This account has no login yet")
    expect(response.body).not_to include('name="hotel_corporate_account[corporate_user][email]"')
  end

  it "returns to the workspace after suspension or reactivation" do
    patch suspend_hotel_corporate_account_path(hotel, relationship), params: { tab: "company_details" }
    expect(relationship.reload).to be_suspended
    expect(response.location).to include("/edit", "tab=company_details")
    patch reactivate_hotel_corporate_account_path(hotel, relationship), params: { tab: "manage_billing" }
    expect(relationship.reload).to be_active
    expect(response.location).to include("/edit", "tab=manage_billing")
  end

  it "scopes editing and updates to the current hotel" do
    other = create(:hotel_corporate_account)
    get edit_hotel_corporate_account_path(hotel, other)
    expect(response).to have_http_status(:not_found)
    patch hotel_corporate_account_path(hotel, other), params: { hotel_corporate_account: { contact_phone: "123" } }
    expect(response).to have_http_status(:not_found)
  end

  it "makes account rows keyboard accessible and keeps More actions independent" do
    relationship
    get hotel_corporate_accounts_path(hotel)
    row = response.parsed_body.at_css("[data-testid='external-account-row-#{relationship.id}']")
    expect(row["role"]).to eq("link")
    expect(row["tabindex"]).to eq("0")
    expect(row["data-action"]).to include("keydown->clickable-row#visitFromKeyboard")
    expect(row["data-clickable-row-url-value"]).to include("/edit")
    account_link = row.at_css('th[scope="row"] a')
    expect(account_link["href"]).to eq(edit_hotel_corporate_account_path(hotel, relationship, return_to: hotel_corporate_accounts_path(hotel)))
    edit = row.at_css("[data-testid='external-account-edit-#{relationship.id}']")
    expect(edit["data-turbo-frame"]).to eq("_top")
  end
end
