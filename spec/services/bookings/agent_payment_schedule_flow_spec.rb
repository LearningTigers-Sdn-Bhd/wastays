# frozen_string_literal: true

require "rails_helper"

# How the amount an agent owes now is worked out, and the bugs that used to let
# a partial payment hold rooms for ever. The services themselves have their own
# specs; this is them working together on one booking.
RSpec.describe "Agent payment schedule lifecycle" do
  let(:hotel) { create(:hotel, status: "live", agent_payment_hold_hours: 72) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:reviewer) { create(:user) }
  let(:now) { Time.zone.parse("2026-09-18 09:00") }
  let(:check_in) { now + 60.days }
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed", payment_status: "pending",
                     total_amount: 1000, currency: "MYR", check_in: check_in, check_out: check_in + 2.days)
  end
  let!(:folio) { create(:booking_folio, booking: booking, hotel: hotel, currency: "MYR") }

  def pay(amount)
    result = Folios::Transactions::InsertTransaction.new(
      booking_folio: folio, amount: amount, transaction_type: "payment", category: "booking_payment",
      user: reviewer, description: "test payment", options: { system_posting: true, posting_source: "spec" }
    ).call
    raise result.error unless result.success?

    Deposits::SyncBookingPaymentStatus.call(booking)
    Bookings::SettlePaymentInstalments.call(booking: booking.reload, folio_transaction: result.transaction, user: reviewer)
  end

  describe Bookings::PaymentProgress do
    before { Bookings::CreatePaymentSchedule.call(booking: booking, from: now) }

    it "asks for the deposit first, then the balance" do
      expect(described_class.new(booking).amount_due_now).to eq(500)
      pay(500)
      expect(described_class.new(booking.reload).amount_due_now).to eq(500)
      pay(500)
      expect(described_class.new(booking.reload).amount_due_now).to be_nil
    end

    it "accepts a slip between the amount due and the amount owed, and refuses the rest" do
      progress = described_class.new(booking)

      expect(progress.amount_problem(500)).to be_nil
      expect(progress.amount_problem(1000)).to be_nil
      expect(progress.amount_problem(499.99)).to include("must be at least MYR 500.00")
      expect(progress.amount_problem(1000.01)).to include("more than the MYR 1000.00 still owed")
    end

    it "asks a booking with no schedule for everything owed" do
      legacy = create(:booking, hotel: hotel, hotel_corporate_account: relationship, total_amount: 300, currency: "MYR")

      expect(described_class.new(legacy).amount_due_now).to eq(300)
    end
  end

  describe "the token payment that used to hold rooms for ever" do
    it "keeps a booking with no schedule on its deadline after a partial payment, so the sweeper still releases it" do
      booking.update!(payment_due_at: 6.hours.from_now)
      pay(1)

      expect(booking.reload.payment_status).to eq("partial")
      expect(booking.payment_due_at).to be_present

      Bookings::ReleaseUnpaidAgentBookings.call(now: 7.hours.from_now)

      expect(booking.reload.status).to eq("cancelled")
    end

    it "releases a scheduled booking that pays the deposit but misses the balance" do
      Bookings::CreatePaymentSchedule.call(booking: booking, from: now)
      pay(500)
      balance_due = booking.reload.payment_instalments.last.due_at

      Bookings::ReleaseUnpaidAgentBookings.call(now: balance_due + 1.minute)

      expect(booking.reload.status).to eq("cancelled")
    end

    it "does not release a scheduled booking between the deposit and the balance deadlines" do
      Bookings::CreatePaymentSchedule.call(booking: booking, from: now)
      pay(500)

      Bookings::ReleaseUnpaidAgentBookings.call(now: now + 10.days)

      expect(booking.reload.status).to eq("confirmed")
    end
  end
end
