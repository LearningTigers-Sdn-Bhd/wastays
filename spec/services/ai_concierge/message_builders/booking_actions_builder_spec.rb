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
end
