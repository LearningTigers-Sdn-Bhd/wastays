# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::VoidBooking, :business_day do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }

  before do
    BusinessDates::ResetAuthority.call!(hotel:, date: Date.current)
  end

  it "voids a booking from every existing lifecycle status" do
    (Booking::STATUSES - %w[voided]).each do |status|
      booking = create(
        :booking,
        hotel:,
        status:,
        no_show_detected_business_date: (Date.current if status == "no_show_detected")
      )

      result = described_class.call(booking:, user:, reason: "Administrative correction")

      expect(result).to be_success, "expected #{status} to be voidable: #{result.error}"
      expect(booking.reload.status).to eq("voided")
    end
  end

  it "leaves open folios and their transactions unchanged" do
    booking = create(:booking, hotel:, status: "confirmed")
    folio = create(:booking_folio, booking:, hotel:, status: "open")
    transaction = create(:folio_transaction, booking_folio: folio, amount: 125)
    folio_attributes = folio.attributes
    transaction_attributes = transaction.attributes

    result = described_class.call(booking:, user:, reason: "Duplicate reservation")

    expect(result).to be_success
    expect(folio.reload.attributes).to eq(folio_attributes)
    expect(transaction.reload.attributes).to eq(transaction_attributes)
  end

  it "does not reopen a closed folio" do
    booking = create(:booking, hotel:, status: "completed")
    folio = create(:booking_folio, booking:, hotel:, status: "closed", closed_at: 1.day.ago, closed_by: user)

    result = described_class.call(booking:, user:, reason: "Invalid completed stay")

    expect(result).to be_success
    expect(folio.reload).to be_closed
  end

  it "ends in-house occupancy, releases remaining inventory, and marks the room dirty" do
    room_type = create(:room_type, hotel:, quantity: 1, room_numbers: [ "101" ])
    booking = create(
      :booking,
      hotel:,
      status: "checked_in",
      checked_in_at: 1.day.ago,
      check_in: Date.current - 1.day,
      check_out: Date.current + 2.days
    )
    create(:booking_room, booking:, room_type:, room_number: "101")
    create(:room_status, hotel:, room_type:, room_number: "101", status: "ready")
    today_inventory = create(:room_inventory, room_type:, date: Date.current, quantity: 0)
    tomorrow_inventory = create(:room_inventory, room_type:, date: Date.current + 1.day, quantity: 0)

    result = described_class.call(booking:, user:, reason: "Booking created in error")

    expect(result).to be_success
    expect(booking.reload.status).to eq("voided")
    expect(today_inventory.reload.quantity).to eq(1)
    expect(tomorrow_inventory.reload.quantity).to eq(1)
    expect(RoomStatus.find_by!(hotel:, room_number: "101").status).to eq("dirty")
    expect(RoomOperationalAuditLog.find_by!(booking:, event_type: "void_booking_marked_dirty").reason).to eq("Booking created in error")
  end

  it "records the previous status, reason, and unchanged-folio contract" do
    booking = create(:booking, hotel:, status: "cancelled")

    result = described_class.call(booking:, user:, reason: "Wrong guest profile")

    expect(result).to be_success
    log = BookingAuditLog.where(auditable: booking, action_type: "void").sole
    expect(log.old_value).to eq("status" => "cancelled")
    expect(log.new_value).to eq("status" => "voided")
    expect(log.metadata).to include(
      "reason" => "Wrong guest profile",
      "previous_status" => "cancelled",
      "folios_unchanged" => true
    )
  end

  it "requires a reason without changing the booking" do
    booking = create(:booking, hotel:, status: "confirmed")

    result = described_class.call(booking:, user:, reason: " ")

    expect(result).not_to be_success
    expect(result.error).to eq("Void reason is required.")
    expect(booking.reload.status).to eq("confirmed")
  end
end
