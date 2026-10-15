# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CreatePaymentSchedule do
  let(:hotel) { create(:hotel, status: "live", agent_payment_hold_hours: 72) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:now) { Time.zone.parse("2026-09-18 09:00") }
  let(:check_in) { now + 60.days }
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed", payment_status: "pending",
                     total_amount: 1000, currency: "MYR", check_in: check_in, check_out: check_in + 2.days)
  end

  it "writes the deposit and balance and points the booking's deadline at the deposit" do
    instalments = described_class.call(booking: booking, from: now)

    expect(instalments.map { |i| [ i.kind, i.amount, i.status ] }).to eq([ [ "deposit", 500, "pending" ], [ "balance", 500, "pending" ] ])
    expect(booking.reload.payment_due_at).to eq(now + 72.hours)
  end

  it "writes one full-amount stage when arrival is too close for two" do
    booking.update!(check_in: now + 10.days, check_out: now + 12.days)

    instalments = described_class.call(booking: booking, from: now)

    expect(instalments.map { |i| [ i.kind, i.amount ] }).to eq([ [ "full", 1000 ] ])
  end

  it "is idempotent" do
    described_class.call(booking: booking, from: now)

    expect { described_class.call(booking: booking, from: now) }.not_to change(BookingPaymentInstalment, :count)
  end

  it "writes nothing for a direct-bill agency" do
    booking.update!(hotel_corporate_account: create(:hotel_corporate_account, :direct_bill, hotel: hotel, account_type: "travel_agent"))

    expect(described_class.call(booking: booking, from: now)).to be_empty
    expect(booking.reload.payment_due_at).to be_nil
  end

  it "keeps the terms it was written under when the hotel changes them later" do
    described_class.call(booking: booking, from: now)
    hotel.update!(agent_deposit_percentage: 90)

    expect(booking.reload.payment_instalments.map(&:amount)).to eq([ 500, 500 ])
  end
end
