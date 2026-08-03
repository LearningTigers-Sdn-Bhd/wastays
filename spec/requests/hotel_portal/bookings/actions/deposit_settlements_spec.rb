# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Checkout deposit settlements", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel, currency: booking.currency) }
  let(:deposit) { create(:deposit, booking: booking, hotel: hotel, amount: 100, currency: folio.currency) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    %w[manage_bookings post_folio_charges].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.humanize)
      create(:role_permission, role: role, permission: permission)
    end
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
    folio
    deposit
  end

  it "renders the reused security-deposit deduction sheet in the secondary frame" do
    get hotel_booking_action_checkout_deposit_settlement_path(hotel, booking, deposit,
      operation: "apply", booking_ids: [ booking.id ]),
      headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("turbo-frame#booking_action_sheet_secondary [data-controller='panels-ui--sheet-frame']")).to be_present
    expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#deposit-settlement-apply-#{deposit.id}")).to be_present
    expect(document.text).to include("Apply deposit", "Cleaning Fee", "Damage Charge", "Miscellaneous Revenue")
  end

  it "posts a reason-coded charge and applies the deposit before closing only its sheet" do
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "damage_revenue")

    expect {
      post hotel_booking_action_checkout_deposit_settlement_path(hotel, booking, deposit,
        operation: "apply", booking_ids: [ booking.id ]),
        params: {
          deposit_settlement: {
            booking_folio_id: folio.id,
            transaction_code_id: code.id,
            amount: "40.00",
            operation_key: "checkout-damage-1"
          }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }
    }.to change { deposit.deposit_movements.movement_type_apply.count }.by(1)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(%(action="complete_sheet"), %(target="booking_action_sheet_secondary"))
    expect(folio.folio_transactions.charge.last).to have_attributes(transaction_code: code, amount: 40.to_d)
    expect(deposit.reload.available_amount).to eq(60.to_d)
  end

  it "releases a security deposit immediately" do
    expect {
      post hotel_booking_action_checkout_deposit_settlement_path(hotel, booking, deposit,
        operation: "release", booking_ids: [ booking.id ]),
        params: {
          deposit_settlement: {
            amount: "25.00", payment_method: "cash", external_reference: "REL-25",
            operation_key: "checkout-release-1"
          }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }
    }.to change { deposit.deposit_movements.movement_type_release.count }.by(1)

    expect(response.body).to include(%(target="booking_action_sheet_secondary"))
    expect(deposit.reload.available_amount).to eq(75.to_d)
  end

  it "offers refund only for prepayments" do
    prepayment = create(:deposit, :prepayment, booking: booking, hotel: hotel, amount: 50, currency: folio.currency)

    get hotel_booking_action_checkout_deposit_settlement_path(hotel, booking, prepayment,
      operation: "refund", booking_ids: [ booking.id ]),
      headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Refund deposit")

    get hotel_booking_action_checkout_deposit_settlement_path(hotel, booking, prepayment,
      operation: "apply", booking_ids: [ booking.id ]),
      headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }
    expect(response).to have_http_status(:not_found)
  end
end
