# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::HotelRelationships", type: :request do
  let(:user) { create(:user, :corporate) }
  let(:relationship) { create(:hotel_corporate_account, corporate_account: user.account) }

  before { sign_in_as(user) }

  it "shows a billing form for a linked hotel" do
    get edit_corporate_hotel_relationship_path(relationship)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Billing details", relationship.hotel.name, "Billing address missing")
    expect(Nokogiri::HTML(response.body).css("select:not([data-panels-ui--combobox-target])")).to be_empty
  end

  it "updates contact and billing address fields" do
    patch corporate_hotel_relationship_path(relationship), params: {
      hotel_corporate_account: {
        contact_email: "billing@acme.test",
        contact_phone: "+60 12-345 6789",
        billing_address_line1: "Lot 8, Jalan Lintas",
        billing_address_line2: "Level 3",
        billing_city: "Kota Kinabalu",
        billing_state: "Sabah",
        billing_postal_code: "88300",
        billing_country: "Malaysia"
      }
    }

    expect(response).to redirect_to(corporate_profile_path)
    expect(relationship.reload).to have_attributes(
      contact_email: "billing@acme.test",
      contact_phone: "+60 12-345 6789",
      billing_address_line1: "Lot 8, Jalan Lintas",
      billing_address_line2: "Level 3",
      billing_city: "Kota Kinabalu",
      billing_state: "Sabah",
      billing_postal_code: "88300",
      billing_country: "Malaysia"
    )
  end

  it "cannot view or update another corporate account's relationship" do
    hidden = create(:hotel_corporate_account)

    get edit_corporate_hotel_relationship_path(hidden)
    expect(response).to have_http_status(:not_found)

    patch corporate_hotel_relationship_path(hidden), params: {
      hotel_corporate_account: { billing_address_line1: "Changed" }
    }
    expect(response).to have_http_status(:not_found)
    expect(hidden.reload.billing_address_line1).to be_nil
  end
end
