require "rails_helper"

RSpec.describe AiConcierge::MessageBuilders::BookingActionsBuilder do
  it "exists" do
    expect(described_class).to be_a(Class)
  end

  it "asks for timing with room-rate context" do
    hotel = build_stubbed(:hotel, name: "Demo Hotel")

    message = described_class.new(hotel: hotel, context: {}).call(:ask_room_rate_timing)

    expect(message).to eq("Dear guest, room rates depend on the booking dates and room types. Which date or month do you plan to arrive for check-in?")
  end

  it "asks for booking timing with arrival phrasing" do
    hotel = build_stubbed(:hotel, name: "Demo Hotel")

    message = described_class.new(hotel: hotel, context: {}).call(:ask_booking_timing)

    expect(message).to eq("Sure, which date or month do you plan to arrive for check-in?")
  end

  it "says hello and what it can do when the booking question opens the thread" do
    hotel = build_stubbed(:hotel, name: "Demo Hotel")

    message = described_class.new(hotel: hotel, context: { opening_reply: true }).call(:ask_booking_timing)

    expect(message).to eq("Hello! I can help you with your booking. Which date or month do you plan to arrive for check-in?")
  end

  it "answers a how-to question before asking anything back" do
    hotel = build_stubbed(:hotel, name: "Demo Hotel")

    message = described_class.new(hotel: hotel, context: { how_to_question: true }).call(:ask_booking_timing)

    expect(message).to eq("I can help you book right here. Which date or month do you plan to arrive for check-in?")
  end

  it "greets and answers at once when a how-to question opens the thread" do
    hotel = build_stubbed(:hotel, name: "Demo Hotel")

    message = described_class.new(hotel: hotel, context: { opening_reply: true, how_to_question: true }).call(:ask_booking_timing)

    expect(message).to eq("Hello! I can help you book right here. Which date or month do you plan to arrive for check-in?")
  end

  it "says what it searched on, and prices rooms from their cheapest plan" do
    hotel = create(:hotel, name: "Demo Hotel")
    context = {
      options: [
        {
          "room_type_name" => "Garden Prestige Suite",
          "options" => [
            {
              "position" => 1,
              "check_in" => "2026-08-28",
              "check_out" => "2026-08-31",
              "nights" => 3,
              "rate_plans" => [
                { "rate_plan_id" => 1, "name" => "Standard Rate", "total_price" => 2940, "currency" => "MYR" },
                { "rate_plan_id" => 2, "name" => "Non-Refundable Rate", "total_price" => 2646, "currency" => "MYR" }
              ]
            }
          ]
        }
      ],
      guest_label: "2 adults",
      search_params: { "check_in" => "2026-08-28", "check_out" => "2026-08-31", "adults" => 2, "room_count" => 1 }
    }

    message = described_class.new(hotel: hotel, context: context).call(:suggest_options)

    expect(message).to include("_28 August 2026 - 31 August 2026 · 3 nights · 2 adults · 1 room_")
    expect(message).to include("*1. Garden Prestige Suite* — from RM 2,646.00")
    expect(message).not_to include("Standard Rate")
    expect(message).not_to include("rate plans")
  end

  it "asks which month for a monthless date range" do
    hotel = build_stubbed(:hotel, name: "Demo Hotel")

    message = described_class.new(hotel: hotel, context: { date_range_label: "16-18" }).call(:ask_date_range_month)

    expect(message).to eq("You said 16-18, but which month?")
  end
end
