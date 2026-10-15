# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::GuestContent::FactCatalogue do
  let(:hotel) { create(:hotel, default_currency: "MYR") }

  it "combines arrival and departure times with the saved guest instructions" do
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "11:00")
    create(:hotel_guest_instruction, hotel: hotel,
      arrival_instructions: "Use the lobby entrance",
      departure_instructions: "Leave the key at reception")

    facts = described_class.new(hotel: hotel).call

    expect(facts.dig("arrival_instructions", "text")).to eq("Check-in is from 3:00 PM. Use the lobby entrance.")
    expect(facts.dig("departure_instructions", "text")).to eq("Check-out is by 11:00 AM. Leave the key at reception.")
  end

  it "formats directions, transport and parking from saved structured content" do
    create(:hotel_transport_detail, hotel: hotel,
      configured_sections: %w[directions transportation parking],
      airport_distance_km: 32,
      airport_travel_minutes: 45,
      directions: "Take exit 14",
      airport_transfer_offered: true,
      airport_transfer_price: 120,
      airport_transfer_lead_hours: 24,
      pickup_point: "Main lobby",
      nearest_transit_stop: "Central station",
      parking_availability: "on_site",
      parking_type: "valet",
      parking_price: 25,
      parking_price_unit: "night",
      parking_spaces: 40,
      parking_height_limit_m: 2.1,
      parking_ev_charging: true,
      parking_booking_required: true)

    facts = described_class.new(hotel: hotel).call

    expect(facts.dig("directions", "text")).to include("32 km", "45 min", "Take exit 14")
    expect(facts.dig("transportation", "text")).to include("offers an airport transfer", "MYR 120.00", "24 hours", "Main lobby", "Central station")
    expect(facts.dig("parking", "text")).to include("On-site", "Valet", "MYR 25.00 per night", "40", "2.1 m", "EV charging", "booking is required")
  end

  it "honours configured negative transport and parking answers" do
    create(:hotel_transport_detail, hotel: hotel,
      configured_sections: %w[transportation parking],
      airport_distance_km: nil,
      airport_travel_minutes: nil,
      directions: nil,
      airport_transfer_offered: false,
      parking_availability: "none")

    facts = described_class.new(hotel: hotel).call

    expect(facts.dig("transportation", "text")).to eq("The hotel does not offer an airport transfer.")
    expect(facts.dig("parking", "text")).to eq("The hotel does not provide guest parking.")
  end

  it "does not infer negative answers from untouched defaults" do
    create(:hotel_transport_detail, hotel: hotel,
      configured_sections: [],
      airport_distance_km: nil,
      airport_travel_minutes: nil,
      directions: nil,
      airport_transfer_offered: false,
      parking_availability: "none")

    facts = described_class.new(hotel: hotel).call

    expect(facts).not_to include("transportation", "parking")
  end

  it "uses guest contacts first and returns static hours and emergency instructions" do
    hotel.update!(contact_phone: "+60 11 0000 0000", contact_email: "hotel@example.com")
    create(:hotel_guest_contact, :with_hours, hotel: hotel,
      front_desk_phone: "+60 3 1234 5678",
      front_desk_extension: "9",
      front_desk_whatsapp: "+60 12 345 6789",
      emergency_instructions: "Leave by the nearest marked exit",
      emergency_phone: "+60 3 9999 9999",
      emergency_services_number: "999")

    facts = described_class.new(hotel: hotel).call

    expect(facts.dig("front_desk_contact", "text")).to include("+60 3 1234 5678", "Extension: 9", "+60 12 345 6789")
    expect(facts.dig("front_desk_contact", "text")).not_to include("+60 11 0000 0000")
    expect(facts.dig("front_desk_hours", "text")).to eq("The front desk is open from 7:00 AM to 11:00 PM.")
    expect(facts.dig("emergency_contact", "text")).to include("nearest marked exit", "+60 3 9999 9999", "999")
  end

  it "reports only Wi-Fi availability and never returns network credentials" do
    create(:hotel_wifi_network, hotel: hotel, ssid: "SecretSSID", password: "secret-password",
      connection_instructions: "Scan the lobby card")

    fact = described_class.new(hotel: hotel).call.fetch("wifi_availability")

    expect(fact["text"]).to include("Guest Wi-Fi is available", "after check-in")
    expect(fact.to_s).not_to include("SecretSSID", "secret-password", "Scan the lobby card")
  end
end
