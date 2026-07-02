require "rails_helper"

RSpec.describe "Public quote guest details", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe Twin") }
  let(:guest) do
    create(
      :guest,
      name: "Aisyah Rahman",
      email: "aisyah@example.com",
      phone: "+60123456789",
      country: "Malaysia",
      gender: "female",
      document_type: "ic",
      government_id: "900101011234",
      date_of_birth: Date.new(1990, 1, 1)
    )
  end
  let(:quote) do
    create(
      :booking_quote,
      hotel: hotel,
      guest_email: guest.email,
      guest_name: guest.name
    )
  end

  before do
    driven_by(:cuprite)
    create(:booking_quote_item, booking_quote: quote, room_type: room_type)
    guest
  end

  it "shows the DOB field after guest details are loaded" do
    visit quote_path(quote.token)

    expect(page).to have_field("Date of Birth", with: "1990-01-01")
    expect(page).to have_field("IC Number", with: "900101011234")
  end
end
