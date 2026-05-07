require "rails_helper"

RSpec.describe AiConciergeV3::Tools::Booking::GenerateBookingUrlTool do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe Room", max_adults: 2) }

  before do
    create(:property_policy, hotel: hotel)
    [ Date.new(2026, 8, 11), Date.new(2026, 8, 12) ].each_with_index do |date, index|
      create(:room_rate, room_type: room_type, date: date, price: 210 + index, currency: "MYR")
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
    end
  end

  it "creates a real booking quote url" do
    result = described_class.new(
      hotel: hotel,
      selected_option: {
        "room_type_id" => room_type.id,
        "check_in" => "2026-08-11",
        "check_out" => "2026-08-13",
        "adults" => 2,
        "children" => 0,
        "room_count" => 1
      },
      guest_phone: "+60123456789"
    ).call

    expect(result["success"]).to be(true)
    expect(result["booking_url"]).to include("/quotes/")
    expect(result["expires_at"]).to be_present
  end
end
