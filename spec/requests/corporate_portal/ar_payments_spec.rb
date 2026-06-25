# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::ArPayments", type: :request do
  let(:user) { create(:user, :corporate) }

  before { sign_in_as(user) }

  it "lists only payments belonging to the current corporate account" do
    relationship = create(:hotel_corporate_account, corporate_account: user.account)
    visible = create(:ar_payment, hotel_corporate_account: relationship, hotel: relationship.hotel, amount: 250, currency: "MYR", reference_number: "PAY-CORP-1")
    hidden = create(:ar_payment, reference_number: "PAY-HIDDEN-1")

    get corporate_ar_payments_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Payment History")
    expect(response.body).to include("PAY-CORP-1")
    expect(response.body).to include(visible.hotel.name)
    expect(response.body).to include("MYR 250.00")
    expect(response.body).not_to include("PAY-HIDDEN-1")
    expect(response.body).not_to include(hidden.hotel.name)
  end
end
