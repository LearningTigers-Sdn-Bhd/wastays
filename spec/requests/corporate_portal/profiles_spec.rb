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
end
