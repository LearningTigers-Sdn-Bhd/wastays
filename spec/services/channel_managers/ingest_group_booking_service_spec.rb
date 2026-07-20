require "rails_helper"

RSpec.describe ChannelManagers::IngestGroupBookingService do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:check_in) { Date.tomorrow }
  let(:check_out) { check_in + 2.days }
  let(:booking_data) do
    {
      hotel: hotel,
      guest_details: { name: "John Doe", email: "john@example.com", phone: "123", country: "US" },
      check_in: check_in,
      check_out: check_out,
      status: "confirmed",
      adults: 2,
      currency: "MYR",
      source: "Expedia",
      external_reference: "EXT123",
      channel_manager_reference: "CM456",
      revision_number: 1,
      rooms: [ { room_type: room_type, quantity: 2, amount: 400.0 } ]
    }
  end

  before do
    (check_in...check_out).each do |date|
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
    end

    allow(Notifications::Dispatcher).to receive(:new)
      .and_return(instance_double(Notifications::Dispatcher, call: []))
  end

  it "creates a group with one child booking and room per unit" do
    result = described_class.new(booking_data: booking_data).call

    expect(result.success?).to be(true), result.message
    expect(result.group_booking).to have_attributes(
      hotel: hotel,
      channel_manager_reference: "CM456",
      external_reference: "EXT123",
      revision_number: 1,
      status: "active"
    )
    expect(result.bookings.size).to eq(2)
    expect(result.bookings).to all(have_attributes(group_booking: result.group_booking, status: "confirmed"))
    expect(result.bookings.map(&:group_position)).to eq([ 1, 2 ])
    expect(result.bookings.map { |booking| booking.booking_rooms.sole.room_type }).to all(eq(room_type))
    expect(result.bookings.map(&:total_amount)).to all(eq(200.0))
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 0, 0 ])
  end

  it "ignores a duplicate revision without changing children, inventory, or audit history" do
    first = described_class.new(booking_data: booking_data).call
    child_ids = first.bookings.map(&:id)
    inventory = room_type.room_inventories.order(:date).pluck(:quantity)
    audit_count = BookingAuditLog.where(auditable: first.group_booking).count

    duplicate = described_class.new(booking_data: booking_data).call

    expect(duplicate.success?).to be(true)
    expect(duplicate.message).to eq("Duplicate or older revision ignored")
    expect(duplicate.group_booking).to eq(first.group_booking)
    expect(duplicate.bookings.map(&:id)).to eq(child_ids)
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq(inventory)
    expect(BookingAuditLog.where(auditable: first.group_booking).count).to eq(audit_count)
  end

  it "reconciles children, rooms, dates, and amounts for a newer revision" do
    other_room_type = create(:room_type, hotel: hotel, name: "Suite", quantity: 2)
    first = described_class.new(booking_data: booking_data).call
    original_ids = first.bookings.map(&:id)
    new_check_in = check_in + 3.days
    new_check_out = check_out + 3.days
    (new_check_in...new_check_out).each do |date|
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
      create(:room_inventory, room_type: other_room_type, date: date, quantity: 2, status: "open")
    end
    revised_data = booking_data.merge(
      check_in: new_check_in,
      check_out: new_check_out,
      revision_number: 2,
      rooms: [
        { room_type: room_type, quantity: 1, amount: 250.0 },
        { room_type: other_room_type, quantity: 2, amount: 500.0 }
      ]
    )

    result = described_class.new(booking_data: revised_data).call

    expect(result.success?).to be(true), result.message
    expect(result.group_booking.revision_number).to eq(2)
    expect(result.bookings.size).to eq(3)
    expect(result.bookings.map(&:id)).to include(*original_ids)
    expect(result.bookings.map { |booking| booking.check_in.to_date }.uniq).to eq([ new_check_in ])
    expect(result.bookings.map { |booking| booking.booking_rooms.sole.room_type }.tally)
      .to eq(room_type => 1, other_room_type => 2)
    expect(result.bookings.map(&:total_amount)).to all(eq(250.0))
    expect(room_type.room_inventories.where(date: check_in...check_out).order(:date).pluck(:quantity)).to eq([ 2, 2 ])
    expect(other_room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 0, 0 ])
  end

  it "cancels every child and releases inventory for a newer revision" do
    first = described_class.new(booking_data: booking_data).call

    result = described_class.new(
      booking_data: booking_data.merge(status: "cancelled", rooms: [], revision_number: 2)
    ).call

    expect(result.success?).to be(true)
    expect(first.group_booking.reload.status).to eq("cancelled")
    expect(result.bookings.map(&:status).uniq).to eq([ "cancelled" ])
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 2, 2 ])
  end

  it "returns a failure and rolls back when a child booking is invalid" do
    invalid_data = booking_data.merge(
      guest_details: booking_data[:guest_details].merge(email: "")
    )

    result = described_class.new(booking_data: invalid_data).call

    expect(result.success?).to be(false)
    expect(result.message).to include("Guest email can't be blank")
    expect(GroupBooking.where(channel_manager_reference: "CM456")).not_to exist
    expect(Booking.where(hotel: hotel)).not_to exist
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 2, 2 ])
  end

  it "aggregates repeated room-type rows before deciding inventory availability" do
    room_type.room_inventories.update_all(quantity: 1)
    repeated_rows = booking_data.merge(
      rooms: [
        { room_type: room_type, quantity: 1, amount: 200.0 },
        { room_type: room_type, quantity: 1, amount: 200.0 }
      ]
    )

    result = described_class.new(booking_data: repeated_rows).call

    expect(result).to be_success
    expect(result.bookings.map(&:status).uniq).to eq([ "overbooked" ])
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 1, 1 ])
  end

  it "releases an assigned room when a no-show-review child is removed" do
    first = described_class.new(booking_data: booking_data).call
    removed = first.bookings.last
    removed.update_columns(status: "review_no_show", no_show_review_business_date: check_in)
    removed.booking_rooms.sole.update!(room_number: "102")

    result = described_class.new(
      booking_data: booking_data.merge(
        revision_number: 2,
        rooms: [ { room_type: room_type, quantity: 1, amount: 200.0 } ]
      )
    ).call

    expect(result).to be_success
    expect(removed.reload.status).to eq("cancelled")
    expect(removed.booking_rooms.sole.reload.room_number).to eq("102")
    expect(RoomStatus.find_by!(hotel: hotel, room_type: room_type, room_number: "102").status).to eq("ready")
    expect(RoomOperationalAuditLog.where(booking: removed, event_type: "review_no_show_cancelled")).to exist
  end
end
