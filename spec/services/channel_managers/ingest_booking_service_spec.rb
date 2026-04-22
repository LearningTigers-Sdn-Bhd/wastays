require "rails_helper"

RSpec.describe ChannelManagers::IngestBookingService do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking_data) do
    {
      hotel: hotel,
      guest_details: { name: "John Doe", email: "john@example.com", phone: "123", country: "US" },
      check_in: Date.tomorrow,
      check_out: Date.tomorrow + 2.days,
      status: "confirmed",
      adults: 2,
      total_amount: 200.0,
      currency: "MYR",
      source: "Expedia",
      external_reference: "EXT123",
      channel_manager_reference: "CM456",
      revision_number: 1,
      rooms: [
        { room_type: room_type, quantity: 1, amount: 200.0 }
      ]
    }
  end

  it "creates a booking from valid data" do
    service = described_class.new(booking_data: booking_data)
    result = service.call

    puts "DEBUG INGEST RESULT: #{result.inspect}"
    expect(result.success?).to be(true)
    expect(result.booking.persisted?).to be(true)
    expect(result.booking.guest_name).to eq("John Doe")
    expect(result.booking.hotel).to eq(hotel)
  end
end
