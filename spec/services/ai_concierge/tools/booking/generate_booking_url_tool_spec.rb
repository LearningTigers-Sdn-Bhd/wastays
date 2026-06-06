require "rails_helper"
require "ostruct"

RSpec.describe AiConcierge::Tools::Booking::GenerateBookingUrlTool do
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

  it "returns a friendly failure when the selected option is missing required ids" do
    result = described_class.new(
      hotel: hotel,
      selected_option: {
        "check_in" => "2026-08-11",
        "check_out" => "2026-08-13"
      },
      guest_phone: "+60123456789"
    ).call

    expect(result).to include(
      "success" => false,
      "error" => "Unable to generate quote right now.",
      "error_code" => "missing_room_type_id"
    )
  end

  it "returns a friendly failure when selected dates are invalid" do
    result = described_class.new(
      hotel: hotel,
      selected_option: {
        "room_type_id" => room_type.id,
        "check_in" => "soon",
        "check_out" => "2026-08-13"
      },
      guest_phone: "+60123456789"
    ).call

    expect(result).to include(
      "success" => false,
      "error" => "Unable to generate quote right now.",
      "error_code" => "invalid_dates"
    )
  end

  it "returns an error code when quote creation fails" do
    quote_service = instance_double(BookingEngine::CreateQuote, call: OpenStruct.new(success?: false, message: "Room is no longer available."))
    allow(BookingEngine::CreateQuote).to receive(:new).and_return(quote_service)

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

    expect(result).to include(
      "success" => false,
      "error" => "Room is no longer available.",
      "error_code" => "quote_creation_failed"
    )
  end

  it "returns a friendly failure when quote creation succeeds without a quote" do
    quote_service = instance_double(BookingEngine::CreateQuote, call: OpenStruct.new(success?: true, quote: nil))
    allow(BookingEngine::CreateQuote).to receive(:new).and_return(quote_service)

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

    expect(result).to include(
      "success" => false,
      "error" => "Unable to generate quote right now.",
      "error_code" => "quote_missing"
    )
  end
end
