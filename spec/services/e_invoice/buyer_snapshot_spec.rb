# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoice::BuyerSnapshot do
  it "captures identity, contact, and a Malaysian stay address" do
    booking = create(:booking,
      guest_name: "John Tan",
      guest_email: "john@example.com",
      guest_phone: "+60123456789",
      guest_country: "Singapore",
      guest_home_address: "No. 12, Jalan Ampang",
      guest_city: "Kuala Lumpur",
      guest_state_code: "14",
      guest_postal_code: "50450",
      guest_address_country: "Malaysia")

    snapshot = described_class.capture(booking)

    expect(snapshot).to include(
      "name" => "John Tan",
      "contact_email" => "john@example.com",
      "contact_phone" => "+60123456789",
      "nationality" => "Singapore"
    )
    expect(snapshot.fetch("billing_address")).to include(
      "address_line1" => "No. 12, Jalan Ampang",
      "city" => "Kuala Lumpur",
      "state_code" => "14",
      "postal_code" => "50450",
      "country" => "Malaysia",
      "country_code" => "MYS"
    )
  end

  it "uses LHDN state code 17 for a foreign postal address" do
    booking = create(:booking,
      guest_home_address: "1 Orchard Road",
      guest_city: "Singapore",
      guest_state_code: nil,
      guest_address_country: "Singapore")

    snapshot = described_class.capture(booking)

    expect(snapshot.dig("billing_address", "state_code")).to eq("17")
    expect(snapshot.dig("billing_address", "country_code")).to eq("SGP")
  end

  it "requires city, address country, and a state for Malaysian addresses" do
    booking = create(:booking, guest_city: nil, guest_address_country: nil)
    expect { described_class.capture(booking) }.to raise_error(ArgumentError, /address country/)

    booking.update!(guest_city: "Unknown City", guest_address_country: "Malaysia", guest_state_code: nil)
    expect { described_class.capture(booking) }.to raise_error(ArgumentError, /buyer state/)
  end
end
