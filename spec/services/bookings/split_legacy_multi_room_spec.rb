# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::SplitLegacyMultiRoom do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel:) }
  let(:booking) do
    create(:booking, hotel:, total_amount: 100.01, margin_amount: 10.01, net_amount: 90,
      tourism_tax_amount: 3.01, tax_lines: [ { "type" => "tax", "rate" => 6.0, "amount" => 3.01 } ])
  end

  before(:context) do
    connection = ActiveRecord::Base.connection
    connection.remove_index(:booking_rooms, name: "idx_booking_rooms_unique_booking") if
      connection.index_exists?(:booking_rooms, :booking_id, name: "idx_booking_rooms_unique_booking")
  end

  after(:context) do
    connection = ActiveRecord::Base.connection
    connection.add_index(:booking_rooms, :booking_id, unique: true, name: "idx_booking_rooms_unique_booking") unless
      connection.index_exists?(:booking_rooms, :booking_id, name: "idx_booking_rooms_unique_booking")
  end

  def add_rooms
    [ 50, 30, 20 ].map do |subtotal|
      id = BookingRoom.insert!({ booking_id: booking.id, room_type_id: room_type.id, subtotal: subtotal,
        room_type_snapshot: {}, nightly_rate_snapshot: {}, occupancy_snapshot: {},
        created_at: Time.current, updated_at: Time.current }, returning: %w[id]).rows.first.first
      BookingRoom.find(id)
    end
  end

  it "reuses the anchor, preserves room ids, allocates amounts, copies safe guests, and records lineage" do
    rooms = add_rooms
    guest_link = create(:booking_guest, booking:, is_primary: true, boat_in_at: Time.current)
    historical_note = create(:booking_note, booking:, user: create(:user), body: "Keep on anchor")

    expect { @result = described_class.call(booking:, metadata: { "run" => "spec" }) }
      .to change(GroupBooking, :count).by(1)
      .and change(Booking, :count).by(2)
      .and change(LegacyBookingSplitLineage, :count).by(3)

    expect(@result).to be_success
    children = @result.bookings.sort_by(&:group_position)
    expect(children.first.id).to eq(booking.id)
    expect(children.flat_map { |child| child.booking_rooms.pluck(:id) }).to match_array(rooms.map(&:id))
    expect(children.map(&:total_amount)).to eq([ 50.01, 30.0, 20.0 ])
    expect(children.sum(&:total_amount)).to eq(100.01)
    expect(children.sum(&:margin_amount)).to eq(10.01)
    expect(children.sum(&:net_amount)).to eq(90)
    expect(children.sum(&:tourism_tax_amount)).to eq(3.01)
    expect(children.sum { |child| child.tax_lines.first.fetch("amount").to_d }).to eq(3.01)
    expect(children.map { |child| child.tax_lines.first.fetch("rate") }).to all(eq(6.0))
    expect(children.drop(1).map { |child| child.booking_guests.first.guest_id }).to all(eq(guest_link.guest_id))
    expect(children.drop(1).map { |child| child.booking_guests.first.boat_in_at }).to all(be_nil)
    expect(historical_note.reload.booking_id).to eq(booking.id)
    expect(LegacyBookingSplitLineage.where(anchor: true).pluck(:child_booking_id)).to eq([ booking.id ])
    expect(BookingAuditLog.where(auditable: booking, action_type: "legacy_multi_room_split")).to exist
  end

  it "does not enqueue booking creation notifications" do
    add_rooms

    expect { described_class.call(booking:) }
      .not_to have_enqueued_job(SendReceiptEmailJob)
    expect { described_class.call(booking:) }
      .not_to have_enqueued_job(SendWhatsappReceiptJob)
  end

  it "is idempotent" do
    add_rooms
    first = described_class.call(booking:)

    expect { @second = described_class.call(booking:) }
      .not_to change { [ GroupBooking.count, Booking.count, LegacyBookingSplitLineage.count ] }
    expect(@second).to be_success
    expect(@second).to be_idempotent
    expect(@second.group_booking).to eq(first.group_booking)
    expect(@second.batch_id).to eq(first.batch_id)
  end

  it "rejects grouped and single-room records" do
    one_room = create(:booking, hotel:)
    create(:booking_room, booking: one_room, room_type:)
    expect(described_class.call(booking: one_room).error).to match(/at least two/)

    add_rooms
    booking.update!(group_booking: create(:group_booking, hotel:), group_position: 1)
    expect(described_class.call(booking:).error).to match(/already assigned/)

  end

  it "splits externally managed financial records with anchor custody and pending review" do
    external = create(
      :booking,
      hotel:,
      source: "ota",
      external_reference: "EXT-1",
      channel_manager_reference: "CM-1",
      revision_number: 4,
      payment_status: "captured",
      payout_status: "pending"
    )
    create(:booking_room, booking: external, room_type:)
    BookingRoom.insert!({ booking_id: external.id, room_type_id: room_type.id, subtotal: 200,
      room_type_snapshot: {}, nightly_rate_snapshot: {}, occupancy_snapshot: {}, created_at: Time.current, updated_at: Time.current })
    create(:payment_transaction, booking: external)

    result = described_class.call(booking: external)

    expect(result).to be_success
    expect(result.group_booking).to have_attributes(
      external_reference: "EXT-1",
      channel_manager_reference: "CM-1",
      revision_number: 4
    )
    expect(external.reload).to have_attributes(
      external_reference: nil,
      channel_manager_reference: nil,
      revision_number: 0,
      payment_status: "captured",
      payout_status: "pending"
    )
    expect(result.bookings.reject { |child| child.id == external.id }).to all(
      have_attributes(payment_status: "pending", payout_status: nil)
    )
    expect(LegacyBookingSplitLineage.where(legacy_booking: external).pluck(:review_status).uniq).to eq([ "pending" ])
  end
end
