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

  before do
    (booking_data[:check_in]...booking_data[:check_out]).each do |date|
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
    end
  end

  it "creates a booking from valid data" do
    dispatcher = instance_double(Notifications::Dispatcher, call: [])
    allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)

    service = described_class.new(booking_data: booking_data)
    result = service.call

    expect(result.success?).to be(true)
    expect(result.booking.persisted?).to be(true)
    expect(result.booking.guest_name).to eq("John Doe")
    expect(result.booking.hotel).to eq(hotel)
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 1, 1 ])
    expect(Notifications::Dispatcher).to have_received(:new).with(event: :booking_confirmed, booking: result.booking)
  end

  it "dispatches booking_updated when existing stay dates change" do
    existing = create(:booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: Date.current + 5.days,
      check_out: Date.current + 7.days)
    data = booking_data.merge(check_in: Date.current + 6.days, check_out: Date.current + 8.days, revision_number: 2)
    (data[:check_in]...data[:check_out]).each do |date|
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
    end
    dispatcher = instance_double(Notifications::Dispatcher, call: [])
    allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)

    result = described_class.new(booking_data: data).call

    expect(result.success?).to be(true)
    expect(existing.reload.check_in.to_date).to eq(Date.current + 6.days)
    expect(Notifications::Dispatcher).to have_received(:new).with(event: :booking_updated, booking: existing)
  end

  it "releases inventory and dispatches cancellation for OTA cancellations" do
    existing = create(:booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "confirmed")
    create(:booking_room, booking: existing, room_type: room_type, quantity: 1)
    room_type.room_inventories.update_all(quantity: 1)
    data = booking_data.merge(status: "cancelled", revision_number: 2)
    dispatcher = instance_double(Notifications::Dispatcher, call: [])
    allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)

    result = described_class.new(booking_data: data).call

    expect(result.success?).to be(true)
    expect(existing.reload.status).to eq("cancelled")
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 2, 2 ])
    expect(Notifications::Dispatcher).to have_received(:new).with(event: :booking_cancelled, booking: existing)
    expect(Notifications::Dispatcher).not_to have_received(:new).with(event: :booking_confirmed, booking: existing)
  end

  it "preserves internal no-show review when the channel still reports confirmed" do
    existing = create(
      :booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "review_no_show",
      no_show_review_business_date: booking_data[:check_in]
    )
    create(:booking_room, booking: existing, room_type: room_type, quantity: 1)

    result = described_class.new(booking_data: booking_data.merge(revision_number: 2)).call

    expect(result.success?).to be(true)
    expect(existing.reload.status).to eq("review_no_show")
  end

  it "allows the channel to cancel a booking pending no-show review" do
    existing = create(
      :booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "review_no_show",
      no_show_review_business_date: booking_data[:check_in]
    )
    create(:booking_room, booking: existing, room_type: room_type, quantity: 1)

    result = described_class.new(booking_data: booking_data.merge(status: "cancelled", revision_number: 2)).call

    expect(result.success?).to be(true)
    expect(existing.reload.status).to eq("cancelled")
  end

  it "marks OTA booking overbooked without deducting inventory when inventory is insufficient" do
    room_type.room_inventories.update_all(quantity: 0)
    dispatcher = instance_double(Notifications::Dispatcher, call: [])
    allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)

    result = described_class.new(booking_data: booking_data).call

    expect(result.success?).to be(true)
    expect(result.booking.status).to eq("overbooked")
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 0, 0 ])
    expect(Notifications::Dispatcher).not_to have_received(:new).with(event: :booking_confirmed, booking: result.booking)
  end

  it "resolves an existing overbooked booking when inventory becomes available" do
    existing = create(:booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "overbooked")
    create(:booking_room, booking: existing, room_type: room_type, quantity: 1)
    data = booking_data.merge(status: "confirmed", revision_number: 2)

    result = described_class.new(booking_data: data).call

    expect(result.success?).to be(true)
    expect(existing.reload.status).to eq("confirmed")
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 1, 1 ])
  end

  it "rejects channel cancellation for a completed booking" do
    existing = create(:booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "completed")
    data = booking_data.merge(status: "cancelled", revision_number: 2)

    result = described_class.new(booking_data: data).call

    expect(result.success?).to be(false)
    expect(result.message).to include("Unsupported status transition from completed to cancelled")
    expect(existing.reload.status).to eq("completed")
  end

  it "rejects channel revival for a cancelled booking" do
    existing = create(:booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "cancelled")
    data = booking_data.merge(status: "confirmed", revision_number: 2)

    result = described_class.new(booking_data: data).call

    expect(result.success?).to be(false)
    expect(result.message).to include("Unsupported status transition from cancelled to confirmed")
    expect(existing.reload.status).to eq("cancelled")
  end

  it "rolls back released inventory when an existing update is invalid" do
    existing = create(:booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "confirmed")
    create(:booking_room, booking: existing, room_type: room_type, quantity: 1)
    room_type.room_inventories.update_all(quantity: 1)
    data = booking_data.merge(guest_details: booking_data[:guest_details].merge(email: ""), revision_number: 2)

    result = described_class.new(booking_data: data).call

    expect(result.success?).to be(false)
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 1, 1 ])
  end

  it "uses persisted dates when an existing modification omits dates" do
    existing = create(:booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "confirmed")
    create(:booking_room, booking: existing, room_type: room_type, quantity: 1)
    data = booking_data.except(:check_in, :check_out).merge(total_amount: 250.0, revision_number: 2)

    result = described_class.new(booking_data: data).call

    expect(result.success?).to be(true)
    expect(existing.reload.total_amount).to eq(250.0)
  end
end
