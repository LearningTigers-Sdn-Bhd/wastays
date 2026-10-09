# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::Profiles", type: :request do
  let(:user) { create(:user, :corporate) }

  before { sign_in_as(user) }

  it "shows the current corporate account profile and linked hotels" do
    relationship = create(:hotel_corporate_account, :direct_bill,
      corporate_account: user.account, credit_limit: 1000, credit_currency: "MYR",
      billing_address_line1: "Lot 8, Jalan Lintas", billing_city: "Kota Kinabalu", billing_country: "Malaysia")
    hidden = create(:hotel_corporate_account)

    get corporate_profile_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Corporate Profile")
    expect(response.body).to include(CGI.escapeHTML(user.account.name))
    expect(response.body).to include(CGI.escapeHTML(user.email))
    expect(response.body).to include(CGI.escapeHTML(relationship.hotel.name))
    expect(response.body).to include("MYR 1,000.00")
    expect(response.body).to include("Lot 8, Jalan Lintas", "Kota Kinabalu", "Edit billing details")
    expect(response.body).to include(edit_corporate_hotel_relationship_path(relationship))
    expect(response.body).not_to include(CGI.escapeHTML(hidden.hotel.name))
  end


  it "warns when a linked hotel's billing address is missing" do
    create(:hotel_corporate_account, corporate_account: user.account)

    get corporate_profile_path

    expect(response.body).to include("Billing address missing")
  end

  it "lets the account holder change their temporary password" do
    hotel = create(:hotel)
    user.update!(temporary_password: "password123", temporary_password_hotel: hotel)
    patch corporate_profile_path, params: { user: {
      current_password: "password123", password: "personal-password", password_confirmation: "personal-password"
    } }
    expect(response).to redirect_to(corporate_profile_path)
    expect(user.reload.temporary_password).to be_nil
    expect(user.authenticate("personal-password")).to eq(user)
  end

  it "retains credentials and shows an error for an incorrect current password" do
    user.update!(temporary_password: "password123", temporary_password_hotel: create(:hotel))
    patch corporate_profile_path, params: { user: {
      current_password: "wrong", password: "personal-password", password_confirmation: "personal-password"
    } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Current password is not correct")
    expect(response.body).not_to include("personal-password", "value=\"wrong\"")
    expect(user.reload.temporary_password).to eq("password123")
  end

  it "does not accept identity changes through the password endpoint" do
    original_email = user.email
    patch corporate_profile_path, params: { user: {
      current_password: "password123", password: "personal-password", password_confirmation: "personal-password", email: "other@example.com"
    } }
    expect(user.reload.email).to eq(original_email)
  end
end
