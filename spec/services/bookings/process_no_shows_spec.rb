# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ProcessNoShows do
  let(:business_date) { Date.new(2026, 5, 18) }
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur") }
  let(:user) { create(:user, account: hotel.account) }
  let(:night_audit_started_at) { Time.find_zone("Kuala Lumpur").local(2026, 5, 19, 2, 10, 0) }
  let(:night_audit) { create(:night_audit, hotel: hotel, business_date: business_date, performed_by_user: user, status: "running", started_at: night_audit_started_at, completed_at: nil) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 5) }

  def create_no_show_candidate(attributes = {})
    booking = create(:booking,
      {
        hotel: hotel,
        status: "confirmed",
        check_in: business_date,
        check_out: business_date + 3.days,
        tax_lines: [ { "name" => "SST", "amount" => "30.00", "type" => "sst" } ],
        tourism_tax_amount: 0
      }.merge(attributes))
    create(:booking_room, booking: booking, room_type: room_type, subtotal: 300.0, quantity: 1)
    booking
  end

  it "marks confirmed arrivals as no-show and posts first-night charges" do
    booking = create_no_show_candidate

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.success?).to be(true)
    expect(result.processed_count).to eq(1)
    expect(booking.reload.status).to eq("no_show")

    folio = booking.booking_folio
    expect(folio).to be_present
    expect(folio.status).to eq("open")
    charge = folio.folio_transactions.charge.where(category: "no_show_charge").sole
    expect(charge.amount).to eq(100.0)
    expect(charge.gl_code).to eq(hotel.hotel_general_ledger_maps.find_by!(transaction_category: "no_show_charge").gl_code)
    expect(folio.folio_transactions.charge.where(category: "tax").sole.amount).to eq(10.0)
    expect(folio.outstanding_balance).to eq(110.0)
  end

  it "uses first-night room and tax snapshots for no-show charges" do
    booking = create_no_show_candidate(
      tax_lines: [],
      tax_posting_snapshot: {
        business_date.iso8601 => [ { "name" => "SST", "amount" => "16.00", "type" => "sst", "source" => "hotel_sst" } ],
        (business_date + 1.day).iso8601 => [ { "name" => "SST", "amount" => "24.00", "type" => "sst", "source" => "hotel_sst" } ]
      }
    )
    booking.booking_rooms.sole.update!(nightly_rate_snapshot: {
      business_date.iso8601 => { "price" => "200.00", "source" => "room_rate" },
      (business_date + 1.day).iso8601 => { "price" => "300.00", "source" => "room_rate" },
      (business_date + 2.days).iso8601 => { "price" => "400.00", "source" => "room_rate" }
    })

    described_class.call(night_audit: night_audit, user: user)

    expect(booking.booking_folio.folio_transactions.charge.where(category: "no_show_charge").sole.amount).to eq(200.0)
    expect(booking.booking_folio.folio_transactions.charge.where(category: "tax").sole.amount).to eq(16.0)
  end

  it "syncs captured payment as a booking payment before posting charge" do
    booking = create_no_show_candidate
    payment_transaction = create(:payment_transaction,
      booking: booking,
      booking_quote: booking.booking_quote,
      status: "captured",
      amount_subunits: 33_000,
      captured_at: business_date.noon)

    described_class.call(night_audit: night_audit, user: user)

    payment = booking.booking_folio.folio_transactions.payment.sole
    expect(payment.category).to eq("booking_payment")
    expect(payment.metadata["payment_transaction_id"]).to eq(payment_transaction.id)
    expect(booking.booking_folio.outstanding_balance).to eq(-220.0)
  end

  it "does not duplicate charges when called repeatedly" do
    booking = create_no_show_candidate

    described_class.call(night_audit: night_audit, user: user)

    expect {
      described_class.call(night_audit: night_audit, user: user)
    }.not_to change { booking.booking_folio.folio_transactions.charge.count }
  end

  it "posts separate no-show tax lines with the same tax type" do
    booking = create_no_show_candidate(
      check_out: business_date + 1.day,
      tax_lines: [
        { "name" => "Local Tax", "amount" => "5.00", "type" => "local" },
        { "name" => "Local Tax", "amount" => "3.00", "type" => "local" }
      ]
    )

    described_class.call(night_audit: night_audit, user: user)

    tax_charges = booking.booking_folio.folio_transactions.charge.where(category: "tax")
    expect(tax_charges.count).to eq(2)
    expect(tax_charges.sum(:amount)).to eq(8.0)
  end

  it "releases only future inventory dates" do
    booking = create_no_show_candidate
    create(:room_inventory, room_type: room_type, date: business_date, quantity: 0)
    create(:room_inventory, room_type: room_type, date: business_date + 1.day, quantity: 0)
    create(:room_inventory, room_type: room_type, date: business_date + 2.days, quantity: 0)

    described_class.call(night_audit: night_audit, user: user)

    expect(room_type.room_inventories.find_by!(date: business_date).quantity).to eq(0)
    expect(room_type.room_inventories.find_by!(date: business_date + 1.day).quantity).to eq(1)
    expect(room_type.room_inventories.find_by!(date: business_date + 2.days).quantity).to eq(1)
    expect(booking.reload.status).to eq("no_show")
  end

  it "does not mark a completed pre-checkin inside the arrival grace period as no-show" do
    booking = create_no_show_candidate
    create(:pre_checkin,
      booking: booking,
      status: "completed",
      completed_at: business_date.to_time,
      metadata: { "estimated_arrival_time" => "01:30" })

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.processed_count).to eq(0)
    expect(booking.reload.status).to eq("confirmed")
  end

  it "marks a completed pre-checkin after the arrival grace period as no-show" do
    booking = create_no_show_candidate
    create(:pre_checkin,
      booking: booking,
      status: "completed",
      completed_at: business_date.to_time,
      metadata: { "estimated_arrival_time" => "23:30" })

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.processed_count).to eq(1)
    expect(booking.reload.status).to eq("no_show")
  end

  it "does not let completed pre-checkin without arrival time create an unlimited hold" do
    booking = create_no_show_candidate
    create(:pre_checkin, booking: booking, status: "completed", completed_at: business_date.to_time, metadata: {})

    described_class.call(night_audit: night_audit, user: user)

    expect(booking.reload.status).to eq("no_show")
  end

  it "releases assigned no-show rooms to ready after the no-show is persisted" do
    booking = create_no_show_candidate
    booking.booking_rooms.sole.update!(room_number: "101")
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

    expect {
      described_class.call(night_audit: night_audit, user: user)
    }.to change(RoomOperationalAuditLog, :count).by(1)

    expect(booking.reload.status).to eq("no_show")
    expect(room_status.reload.status).to eq("ready")

    log = RoomOperationalAuditLog.last
    expect(log.event_type).to eq("no_show_released_after_night_audit")
    expect(log.booking).to eq(booking)
    expect(log.metadata["night_audit_id"]).to eq(night_audit.id)
  end

  it "creates a ready room status when releasing an assigned no-show room without an existing status row" do
    booking = create_no_show_candidate
    booking.booking_rooms.sole.update!(room_number: "101")

    described_class.call(night_audit: night_audit, user: user)

    room_status = RoomStatus.find_by!(hotel: hotel, room_type: room_type, room_number: "101")
    expect(room_status.status).to eq("ready")
  end

  it "allows a released no-show room to be assigned to another booking" do
    booking = create_no_show_candidate
    booking.booking_rooms.sole.update!(room_number: "101")
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")
    next_booking = create_no_show_candidate(check_in: business_date + 1.day, check_out: business_date + 2.days)

    described_class.call(night_audit: night_audit, user: user)
    result = Bookings::AssignRoom.new(booking: next_booking, room_number: "101", user: user).call

    expect(result).to be_success
    expect(next_booking.booking_rooms.reload.first.room_number).to eq("101")
  end

  it "ignores bookings that are not confirmed arrivals for the business date" do
    checked_in = create_no_show_candidate(status: "checked_in")
    future = create_no_show_candidate(check_in: business_date + 1.day, check_out: business_date + 2.days)
    cancelled = create_no_show_candidate(status: "cancelled")

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.processed_count).to eq(0)
    expect(checked_in.reload.status).to eq("checked_in")
    expect(future.reload.status).to eq("confirmed")
    expect(cancelled.reload.status).to eq("cancelled")
  end

  it "records a booking audit log" do
    booking = create_no_show_candidate

    expect {
      described_class.call(night_audit: night_audit, user: user)
    }.to change(BookingAuditLog, :count).by(1)

    log = BookingAuditLog.last
    expect(log.auditable).to eq(booking)
    expect(log.action_type).to eq("no_show")
    expect(log.metadata["night_audit_id"]).to eq(night_audit.id)
  end
end
