require "rails_helper"

RSpec.describe AiConciergeV3::MessengerAgent do
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  it "renders the hotel-specific greeting" do
    result = described_class.new(hotel: hotel, context: { reply_type: :greeting }).call

    expect(result["reply_message"]).to eq("Hello, welcome to #{hotel.name}! I can help with bookings, stay details, and more about the hotel. What would you like to inquire about?")
  end

  it "renders grouped booking suggestions by room type" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :suggest_options,
      month_label: "early August 2026",
      guest_label: "2 adults",
      options: [
        {
          "room_type_name" => "Garden Prestige Suite",
          "options" => [
            { "position" => 1, "check_in" => "2026-08-03", "check_out" => "2026-08-05", "currency" => "MYR", "total_price" => 520.0 },
            { "position" => 2, "check_in" => "2026-08-04", "check_out" => "2026-08-06", "currency" => "USD", "total_price" => 120.0 }
          ]
        }
      ]
    }).call

    expect(result["reply_message"]).to include("Garden Prestige Suite")
    expect(result["reply_message"]).to include("1. RM 520.00 : Check-in *August 3* - Check-out *August 5*")
    expect(result["reply_message"]).to include("2. USD 120.00 : Check-in *August 4* - Check-out *August 6*")
    expect(result["reply_message"]).to include('Reply with the room type name and option number or date you want, for example: "Ocean Villa King option 1" or "Executive Penthouse on May 21".')
  end

  it "renders the narrowed room type options when asking for an option number" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :room_type_requires_option_number,
      room_type_name: "Executive Penthouse",
      room_options: {
        "room_type_name" => "Executive Penthouse",
        "options" => [
          { "position" => 1, "check_in" => "2026-08-03", "check_out" => "2026-08-05", "currency" => "MYR", "total_price" => 520.0 },
          { "position" => 2, "check_in" => "2026-08-04", "check_out" => "2026-08-06", "currency" => "MYR", "total_price" => 540.0 }
        ]
      }
    }).call

    expect(result["reply_message"]).to include("I found multiple options under Executive Penthouse:")
    expect(result["reply_message"]).to include("1. RM 520.00 : Check-in *August 3* - Check-out *August 5*")
    expect(result["reply_message"]).to include("Please tell me the option number you want.")
  end

  it "renders confirmation with yes and no prompt" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :ask_confirmation,
      selected_option: {
        "room_type_name" => "Executive Penthouse",
        "check_in" => "2026-08-03",
        "check_out" => "2026-08-05",
        "currency" => "MYR",
        "total_price" => 520.0
      }
    }).call

    expect(result["reply_message"]).to eq("You'd like Executive Penthouse from August 3 to August 5 for RM 520.00. Please reply *Yes* or *No*.")
  end

  it "renders hotel policy as a multiline block" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :hotel_policy,
      result: {
        "check_in_time" => "15:00",
        "check_out_time" => "12:00",
        "cancellation_policy" => "24 hours"
      }
    }).call

    expect(result["reply_message"]).to eq([
      "Welcome to #{hotel.name}! Here is our hotel policy:",
      "- Check-in starts at: *15:00*",
      "- Check-out is at: *12:00*",
      "- Cancellation: *24 hours*"
    ].join("\n"))
  end

  it "renders a structured booking context list" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :booking_context,
      bookings: [
        { "date_range" => "May 21 - May 23", "room_type_name" => "Executive Penthouse" }
      ]
    }).call

    expect(result["reply_message"]).to include("According to our system, we found your active booking:")
    expect(result["reply_message"]).to include("- *May 21 - May 23*: Executive Penthouse")
  end

  it "renders an empty booking context state" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :booking_context,
      bookings: []
    }).call

    expect(result["reply_message"]).to eq("According to our system, we could not find an active booking at the moment.")
  end
end
