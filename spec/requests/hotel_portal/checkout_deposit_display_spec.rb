# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Checkout Deposit Display", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, role: "superadmin") }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }

  before do
    sign_in_as(user)
    # Ensure some charges exist to make the folio valid for checkout view
    create(:booking_room, booking: booking, subtotal: 100.0)
    # Give user permissions
    user.user_hotel_accesses.create!(hotel: hotel, role: create(:role, permissions: [
      Permission.find_or_create_by!(slug: "manage_bookings") { |p| p.name = "Manage Bookings" },
      Permission.find_or_create_by!(slug: "view_bookings") { |p| p.name = "View Bookings" },
      Permission.find_or_create_by!(slug: "manage_guest_arrival") { |p| p.name = "Manage Guest Arrival" }
    ]))
  end

  it "renders held security deposits in the checkout sheet" do
    create(:deposit,
      booking: booking,
      hotel: hotel,
      booking_folio: folio,
      amount: 250.0,
      status: "held",
      payment_method: "cash"
    )

    get hotel_booking_transaction_check_out_path(hotel, booking), headers: { "Accept" => "text/html" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("MYR 250.00")
    expect(response.body).to include("held independently from the folio")
    expect(response.body).to include("Return security deposit at checkout")

    document = Nokogiri::HTML(response.body)
    toggle = document.at_css('input[name="release_security_deposit"][type="checkbox"]')
    expect(toggle["value"]).to eq("1")
    expect(toggle).to have_attribute("checked")
    expect(document.at_css('input[name="release_security_deposit"][type="hidden"]')["value"]).to eq("0")
    expect(document.css('#security_deposit_release_method option').map(&:text)).to eq(
      [ "Cash returned", "Card released", "Bank transfer", "Other/manual" ]
    )
    expect(document.css('select[name$="[payment_method]"] option').map(&:text)).to eq(
      [ "Cash", "Card", "Bank transfer", "Manual recovery" ]
    )
    expect(response.body).not_to include("<span>Off</span>")
    expect(response.body).not_to include("<span>On</span>")
  end

  it "does not render the deposits section if no deposits are held" do
    get hotel_booking_transaction_check_out_path(hotel, booking), headers: { "Accept" => "text/html" }

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include("Return security deposit at checkout")
  end

  it "preserves an OFF release choice and reference after a checkout error" do
    create(:deposit, booking: booking, hotel: hotel, booking_folio: folio, amount: 250, status: "held")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100)

    post check_out_hotel_booking_path(hotel, booking),
      params: {
        checkout_sheet: "1",
        release_security_deposit: "0",
        security_deposit_release_method: "bank_transfer",
        security_deposit_release_reference: "KEEP-REF"
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:unprocessable_content)
    document = Nokogiri::HTML(response.body)
    toggle = document.at_css('input[name="release_security_deposit"][type="checkbox"]')
    expect(toggle).not_to have_attribute("checked")
    expect(document.at_css("#security_deposit_release_method")).to have_attribute("disabled")
    expect(document.at_css("#security_deposit_release_method option[selected]")["value"]).to eq("bank_transfer")
    expect(document.at_css("#security_deposit_release_reference")["value"]).to eq("KEEP-REF")
  end
end
