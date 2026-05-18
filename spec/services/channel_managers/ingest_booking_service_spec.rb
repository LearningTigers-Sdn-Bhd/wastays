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
    # Create inventory for the dates to avoid overbooking
    (booking_data[:check_in]..(booking_data[:check_out] - 1.day)).each do |date|
      create(:room_inventory, room_type: room_type, date: date, quantity: 5)
    end

    dispatcher = instance_double(Notifications::Dispatcher, call: [])
    allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)

    service = described_class.new(booking_data: booking_data)
    result = service.call

    expect(result.success?).to be(true)
    expect(result.booking.persisted?).to be(true)
    expect(result.booking.guest_name).to eq("John Doe")
    expect(result.booking.hotel).to eq(hotel)
    expect(Notifications::Dispatcher).to have_received(:new).with(event: :booking_confirmed, booking: result.booking)
  end

  it "dispatches booking_updated when existing stay dates change" do
    existing = create(:booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: Date.current + 5.days,
      check_out: Date.current + 7.days)
    data = booking_data.merge(check_in: Date.current + 6.days, check_out: Date.current + 8.days, revision_number: 2)
    dispatcher = instance_double(Notifications::Dispatcher, call: [])
    allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)

    result = described_class.new(booking_data: data).call

    expect(result.success?).to be(true)
    expect(existing.reload.check_in).to eq(Date.current + 6.days)
    expect(Notifications::Dispatcher).to have_received(:new).with(event: :booking_updated, booking: existing)
  end
end
