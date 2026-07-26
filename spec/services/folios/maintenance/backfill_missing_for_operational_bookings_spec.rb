# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Maintenance::BackfillMissingForOperationalBookings do
  it "creates missing folios for operational bookings and remains idempotent" do
    booking = create(:booking, status: "confirmed")
    create(:booking_room, booking: booking, subtotal: 100)

    first_result = described_class.call(scope: Booking.where(id: booking.id))
    second_result = described_class.call(scope: Booking.where(id: booking.id))

    expect(first_result.created.sole["booking_id"]).to eq(booking.id)
    expect(second_result.skipped.sole["reason"]).to eq("Booking already has a folio.")
    expect(booking.reload.booking_folio).to be_present
    expect(BookingFolio.where(booking: booking).count).to eq(1)
  end

  it "skips cancelled and completed bookings" do
    cancelled = create(:booking, status: "cancelled")
    completed = create(:booking, status: "completed")

    result = described_class.call(scope: Booking.where(id: [ cancelled.id, completed.id ]))

    expect(result.created).to be_empty
    expect(cancelled.reload.booking_folio).to be_nil
    expect(completed.reload.booking_folio).to be_nil
  end

  it "skips hotels while Night Audit is running" do
    booking = create(:booking, status: "checked_in")
    booking.hotel.current_business_date_record.update!(status: "audit_running")

    result = described_class.call(scope: Booking.where(id: booking.id))

    expect(result.skipped.sole["reason"]).to eq("Night Audit is currently running.")
    expect(booking.reload.booking_folio).to be_nil
  end

  it "reports failures without preventing other bookings from being initialized" do
    failed_booking = create(:booking, status: "confirmed")
    successful_booking = create(:booking, status: "confirmed")
    allow(Folios::InitializeForBooking).to receive(:call).and_call_original
    allow(Folios::InitializeForBooking).to receive(:call).with(booking: failed_booking, user: nil).and_raise("sync failed")

    result = described_class.call(scope: Booking.where(id: [ failed_booking.id, successful_booking.id ]))

    expect(result.failed.sole["booking_id"]).to eq(failed_booking.id)
    expect(result.created.sole["booking_id"]).to eq(successful_booking.id)
  end
end
