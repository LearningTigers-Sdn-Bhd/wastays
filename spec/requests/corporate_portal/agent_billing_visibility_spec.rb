# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal Agent Billing Visibility", type: :request do
  let(:hotel) { create(:hotel, default_currency: "MYR") }
  let(:staff_user) { create(:user) }
  let(:agent_account) do
    create(
      :hotel_corporate_account,
      hotel: hotel,
      account_type: "travel_agent",
      direct_bill_enabled: true,
      payment_terms_days: 30,
      credit_currency: "MYR",
      corporate_account: create(:account, :corporate, name: "Sunset Travel Agency")
    )
  end
  let(:corporate_user) { create(:user, account: agent_account.corporate_account, role: "corporate") }

  it "gives the agent's corporate portal user visibility into the invoice generated from their booking" do
    booking = create(:booking, hotel: hotel, status: "checked_in", currency: "MYR", hotel_corporate_account: agent_account)
    create(:booking_room, booking: booking, subtotal: 300.0)
    folio = Folios::InitializeForBooking.call(booking: booking, user: staff_user)
    folio.folio_forecasted_charges.forecast.each do |forecast|
      key = Folios::ChargePostingKeys.nightly_charge_key(
        booking: booking, date: forecast.stay_date, charge_kind: forecast.charge_kind, identity: forecast.identity
      )
      create(:folio_transaction,
        booking_folio: folio,
        transaction_type: :charge,
        category: forecast.charge_kind,
        amount: forecast.amount,
        metadata: { nightly_charge_key: key })
    end
    Folios::CloseForCheckout.call(booking: booking, user: staff_user, options: { direct_bill_folio_ids: [ folio.id ] })

    sign_in_as(corporate_user)
    get corporate_dashboard_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Outstanding balance")
    expect(response.body).to include("MYR 300.00")

    get corporate_ar_invoices_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(folio.reload.ar_invoice.invoice_number.to_s)
  end
end
