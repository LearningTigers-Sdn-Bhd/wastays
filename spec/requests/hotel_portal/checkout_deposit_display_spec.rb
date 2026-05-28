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
      create(:permission, slug: "manage_bookings"),
      create(:permission, slug: "view_bookings"),
      create(:permission, slug: "manage_guest_arrival")
    ]))
  end

  it "renders held security deposits in the checkout sheet" do
    create(:deposit, 
      booking: booking, 
      hotel: hotel, 
      booking_folio: folio, 
      amount: 250.0, 
      status: "collected", 
      payment_method: "cash"
    )

    get checkout_hotel_booking_path(hotel, booking), headers: { "Accept" => "text/html" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Security Deposit Status")
    expect(response.body).to include("Current Status")
    expect(response.body).to include("Collected")
    expect(response.body).to include("Security deposits are tracked independently from the folio")
  end

  it "does not render the deposits section if no deposits are held" do
    get checkout_hotel_booking_path(hotel, booking), headers: { "Accept" => "text/html" }

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include("Held Security Deposits")
  end
end
