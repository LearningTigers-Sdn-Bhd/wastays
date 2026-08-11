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
    expect(result.booking.primary_guest).to have_attributes(name: "John Doe", email: "john@example.com")
    expect(result.booking.primary_guest.metadata).to include(
      "profile_source" => "channel_manager",
      "profile_incomplete" => true
    )
    expect(result.booking.hotel).to eq(hotel)
    expect(result.booking.booking_billing_parties.guests.active.sole.booking_guest).to eq(result.booking.booking_guests.sole)
    expect(result.booking.booking_folio).to have_attributes(
      is_primary: true,
      payer_type: "guest",
      booking_billing_party: result.booking.booking_billing_parties.guests.active.sole
    )
    expect(result.booking.booking_folio.folio_forecasted_charges).not_to be_empty
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 1, 1 ])
    expect(Notifications::Dispatcher).to have_received(:new).with(event: :booking_confirmed, booking: result.booking)
  end

  it "never mutates another hotel's booking with the same channel reference" do
    other_hotel = create(:hotel)
    other_booking = create(:booking, hotel: other_hotel, channel_manager_reference: "CM456", guest_name: "Other tenant")

    result = described_class.new(booking_data: booking_data).call

    expect(result).to be_success
    expect(result.booking.hotel).to eq(hotel)
    expect(result.booking).not_to eq(other_booking)
    expect(other_booking.reload.guest_name).to eq("Other tenant")
  end

  it "rolls back the booking when required connections cannot be initialized" do
    allow(ChannelManagers::InitializeBookingConnections).to receive(:call!).and_raise("folio initialization failed")

    result = described_class.new(booking_data: booking_data).call

    expect(result).not_to be_success
    expect(result.message).to include("folio initialization failed")
    expect(Booking.where(channel_manager_reference: "CM456")).not_to exist
    expect(Guest.where(email: "john@example.com")).not_to exist
    expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 2, 2 ])
  end

  it "converts OTA money into hotel currency and records the source values" do
    hotel.update!(default_currency: "MYR")
    create(:exchange_rate, base_currency: "USD", currency_code: "MYR", rate: 4.1)

    result = described_class.new(
      booking_data: booking_data.merge(currency: "USD", total_amount: 100, rooms: [
        { room_type: room_type, quantity: 1, amount: 100 }
      ])
    ).call

    expect(result).to be_success
    expect(result.booking).to have_attributes(currency: "MYR", total_amount: 410.to_d)
    expect(result.booking.booking_rooms.sole.subtotal).to eq(410.to_d)
    audit = BookingAuditLog.where(auditable: result.booking, action_type: "external_creation").last
    expect(audit.metadata.fetch("currency_conversion")).to include(
      "source_currency" => "USD",
      "target_currency" => "MYR",
      "source_total_amount" => "100.0",
      "converted_total_amount" => "410.0"
    )
  end

  it "does not ingest or acknowledge unsafe money when its exchange rate is missing" do
    result = described_class.new(booking_data: booking_data.merge(currency: "USD")).call

    expect(result).not_to be_success
    expect(result.message).to eq("Missing exchange rate from USD to MYR")
    expect(Booking.where(channel_manager_reference: "CM456")).not_to exist
  end

  it "does not discard a distinct opaque revision that shares a numeric timestamp gate" do
    existing = create(:booking,
      hotel: hotel, channel_manager_reference: "CM456", revision_number: 10,
      check_in: booking_data[:check_in], check_out: booking_data[:check_out], status: "confirmed", adults: 1)
    create(:booking_room, booking: existing, room_type: room_type)

    result = described_class.new(
      booking_data: booking_data.merge(revision_id: "opaque-revision-2", revision_number: 10, adults: 3)
    ).call

    expect(result).to be_success
    expect(existing.reload.adults).to eq(3)
  end

  it "keeps a manually assigned room when a later revision arrives" do
    room_type.update!(quantity: 2, room_numbers: %w[101 102])
    existing = create(:booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "confirmed")
    create(:booking_room, booking: existing, room_type: room_type, room_number: "102")

    result = described_class.new(booking_data: booking_data.merge(revision_number: 2, adults: 3)).call

    expect(result).to be_success
    expect(result.booking.booking_rooms.sole.room_number).to eq("102")
  end

  it "automatically assigns an available physical room" do
    room_type.update!(quantity: 2, room_numbers: %w[101 102])

    result = described_class.new(booking_data: booking_data).call

    expect(result).to be_success
    expect(result.booking.booking_rooms.sole.room_number).to eq("101")
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
    create(:booking_room, booking: existing, room_type: room_type)
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

  it "retains financial projections for an incomplete room-shell cancellation" do
    existing = create(:booking,
      hotel: hotel, channel_manager_reference: "CM456",
      check_in: booking_data[:check_in], check_out: booking_data[:check_out],
      status: "confirmed", total_amount: 200)
    room = create(:booking_room, booking: existing, room_type: room_type, subtotal: 200,
      nightly_rate_snapshot: { booking_data[:check_in].iso8601 => { "price" => "100.0" } })
    data = booking_data.merge(
      status: "cancelled", revision_number: 2, total_amount: nil,
      rooms: [ { room_type: room_type, quantity: 1, amount: nil } ],
      financials: { breakdown_present: true, breakdown_complete: false, rooms: [ { amount: 0.to_d } ] }
    )

    result = described_class.new(booking_data: data).call

    expect(result).to be_success
    expect(existing.reload).to have_attributes(status: "cancelled", total_amount: 200.to_d)
    expect(room.reload).to have_attributes(subtotal: 200.to_d)
    expect(room.nightly_rate_snapshot).to eq(booking_data[:check_in].iso8601 => { "price" => "100.0" })
  end

  it "preserves an internally detected no-show when the channel still reports confirmed" do
    existing = create(
      :booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "no_show_detected",
      no_show_detected_business_date: booking_data[:check_in]
    )
    create(:booking_room, booking: existing, room_type: room_type)

    result = described_class.new(booking_data: booking_data.merge(revision_number: 2)).call

    expect(result.success?).to be(true)
    expect(existing.reload.status).to eq("no_show_detected")
  end

  it "allows the channel to cancel a booking with a detected no-show" do
    existing = create(
      :booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "no_show_detected",
      no_show_detected_business_date: booking_data[:check_in]
    )
    create(:booking_room, booking: existing, room_type: room_type)

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
    create(:booking_room, booking: existing, room_type: room_type)
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
    create(:booking_room, booking: existing, room_type: room_type)
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
    create(:booking_room, booking: existing, room_type: room_type)
    data = booking_data.except(:check_in, :check_out).merge(total_amount: 250.0, revision_number: 2)

    result = described_class.new(booking_data: data).call

    expect(result.success?).to be(true)
    expect(existing.reload.total_amount).to eq(250.0)
  end

  it "records one semantic event with readable room revisions" do
    other_room_type = create(:room_type, hotel: hotel, name: "Suite")
    existing = create(
      :booking,
      hotel: hotel,
      channel_manager_reference: "CM456",
      check_in: booking_data[:check_in],
      check_out: booking_data[:check_out],
      status: "confirmed"
    )
    create(:booking_room, booking: existing, room_type: room_type)
    data = booking_data.merge(
      rooms: [ { room_type: other_room_type, quantity: 2, amount: 200.0 } ],
      revision_number: 2
    )
    (data[:check_in]...data[:check_out]).each do |date|
      create(:room_inventory, room_type: other_room_type, date: date, quantity: 3, status: "open")
    end

    result = nil
    expect { result = described_class.new(booking_data: data).call }
      .to change { BookingAuditLog.where(auditable_type: "GroupBooking").count }.by(1)

    audit = BookingAuditLog.where(auditable: result.group_booking).last
    expect(audit.old_value["rooms"]).to include(a_string_including(room_type.name))
    expect(audit.new_value["rooms"]).to eq([ "2x Suite" ])
  end

  describe "multi-room reservations" do
    let(:multi_room_data) do
      booking_data.merge(
        total_amount: 400.0,
        rooms: [ { room_type: room_type, quantity: 2, amount: 400.0 } ]
      )
    end

    it "creates one channel-owned group with one individually addressable booking per room" do
      result = described_class.new(booking_data: multi_room_data).call

      expect(result.success?).to be(true), result.message
      expect(result.group_booking).to have_attributes(
        hotel: hotel,
        channel_manager_reference: "CM456",
        external_reference: "EXT123",
        revision_number: 1
      )
      expect(result.bookings.size).to eq(2)
      expect(result.booking).to eq(result.bookings.first)
      expect(result.bookings).to all(have_attributes(group_booking: result.group_booking))
      expect(result.bookings.map { |booking| booking.booking_rooms.count }).to eq([ 1, 1 ])
      expect(result.bookings).to all(have_attributes(channel_manager_reference: nil, external_reference: nil))
      expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 0, 0 ])
    end

    it "converts OTA money and records the source values on the group audit" do
      hotel.update!(default_currency: "MYR")
      create(:exchange_rate, base_currency: "USD", currency_code: "MYR", rate: 4.1)

      result = described_class.new(booking_data: multi_room_data.merge(currency: "USD")).call

      expect(result).to be_success
      expect(result.bookings).to all(have_attributes(currency: "MYR", total_amount: 820.to_d))
      audit = BookingAuditLog.where(auditable: result.group_booking).last
      expect(audit.metadata.fetch("currency_conversion")).to include(
        "source_currency" => "USD",
        "target_currency" => "MYR",
        "source_total_amount" => "400.0",
        "converted_total_amount" => "1640.0"
      )
    end

    it "automatically assigns a distinct physical room to each child" do
      room_type.update!(quantity: 2, room_numbers: %w[101 102])

      result = described_class.new(booking_data: multi_room_data).call

      expect(result).to be_success
      expect(result.bookings.map { |booking| booking.booking_rooms.sole.room_number }).to eq(%w[101 102])
    end

    it "ignores duplicate and older revisions without touching children, inventory, or audit" do
      first = described_class.new(booking_data: multi_room_data).call
      child_ids = first.bookings.map(&:id)
      inventory = room_type.room_inventories.order(:date).pluck(:quantity)
      audit_count = BookingAuditLog.where(auditable: first.group_booking).count

      duplicate = described_class.new(booking_data: multi_room_data).call
      older = described_class.new(booking_data: multi_room_data.merge(revision_number: 0)).call

      expect(duplicate.success?).to be(true)
      expect(older.success?).to be(true)
      expect(duplicate.bookings.map(&:id)).to eq(child_ids)
      expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq(inventory)
      expect(BookingAuditLog.where(auditable: first.group_booking).count).to eq(audit_count)
    end

    it "updates children in place while reconciling dates, categories, and quantity" do
      other_room_type = create(:room_type, hotel: hotel, name: "Suite")
      first = described_class.new(booking_data: multi_room_data).call
      original_ids = first.bookings.map(&:id)
      new_check_in = booking_data[:check_in] + 3.days
      new_check_out = booking_data[:check_out] + 3.days
      (new_check_in...new_check_out).each do |date|
        create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
        create(:room_inventory, room_type: other_room_type, date: date, quantity: 2, status: "open")
      end
      revised_data = multi_room_data.merge(
        check_in: new_check_in,
        check_out: new_check_out,
        revision_number: 2,
        rooms: [
          { room_type: room_type, quantity: 1, amount: 200.0 },
          { room_type: other_room_type, quantity: 2, amount: 400.0 }
        ]
      )

      result = described_class.new(booking_data: revised_data).call

      expect(result.success?).to be(true), result.message
      expect(result.bookings.size).to eq(3)
      expect(result.bookings.map(&:id)).to include(*original_ids)
      expect(result.bookings.map { |booking| booking.booking_rooms.count }).to eq([ 1, 1, 1 ])
      expect(result.bookings.map { |booking| booking.check_in.to_date }.uniq).to eq([ new_check_in ])
      expect(result.bookings.map { |booking| booking.status }.uniq).to eq([ "confirmed" ])
      expect(result.bookings.map { |booking| booking.booking_rooms.first.room_type.name }.tally)
        .to eq(room_type.name => 1, "Suite" => 2)
      expect(room_type.room_inventories.where(date: booking_data[:check_in]...booking_data[:check_out]).order(:date).pluck(:quantity)).to eq([ 2, 2 ])
      expect(other_room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 0, 0 ])
    end

    it "cancels and retains the surplus child when room quantity decreases" do
      first = described_class.new(booking_data: multi_room_data).call
      original_ids = first.bookings.map(&:id)

      result = described_class.new(booking_data: booking_data.merge(revision_number: 2)).call

      expect(result.success?).to be(true), result.message
      expect(result.bookings.size).to eq(2)
      expect(original_ids).to include(result.booking.id)
      expect(result.booking.booking_rooms.count).to eq(1)
      expect(first.group_booking.bookings.reload.pluck(:id)).to match_array(original_ids)
      expect(result.bookings.map(&:status).tally).to eq("confirmed" => 1, "cancelled" => 1)
      expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 1, 1 ])
    end

    it "cancels every child and releases each room's inventory on a newer revision" do
      first = described_class.new(booking_data: multi_room_data).call

      result = described_class.new(booking_data: multi_room_data.merge(status: "cancelled", rooms: [], revision_number: 2)).call

      expect(result.success?).to be(true), result.message
      expect(first.group_booking.reload.status).to eq("cancelled")
      expect(result.bookings.map(&:status).uniq).to eq([ "cancelled" ])
      expect(room_type.room_inventories.order(:date).pluck(:quantity)).to eq([ 2, 2 ])
    end
  end
end
