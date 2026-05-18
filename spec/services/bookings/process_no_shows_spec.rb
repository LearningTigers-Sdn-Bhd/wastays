# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ProcessNoShows do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:night_audit) { create(:night_audit, hotel: hotel, business_date: business_date, performed_by_user: user, status: "running") }
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

  it "marks confirmed arrivals as no-show and posts first-night penalties" do
    booking = create_no_show_candidate

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.success?).to be(true)
    expect(result.processed_count).to eq(1)
    expect(booking.reload.status).to eq("no_show")

    folio = booking.booking_folio
    expect(folio).to be_present
    expect(folio.status).to eq("open")
    expect(folio.folio_transactions.charge.where(category: "accommodation").sole.amount).to eq(100.0)
    expect(folio.folio_transactions.charge.where(category: "tax").sole.amount).to eq(10.0)
    expect(folio.outstanding_balance).to eq(110.0)
  end

  it "syncs captured payment as an advance deposit before posting penalty" do
    booking = create_no_show_candidate
    payment_transaction = create(:payment_transaction, booking: booking, booking_quote: booking.booking_quote, status: "captured", amount_subunits: 33_000)

    described_class.call(night_audit: night_audit, user: user)

    payment = booking.booking_folio.folio_transactions.payment.sole
    expect(payment.category).to eq("advance_deposit")
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
