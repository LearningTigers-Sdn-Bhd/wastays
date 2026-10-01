# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::SettlePaymentInstalments do
  let(:hotel) { create(:hotel, status: "live", agent_payment_hold_hours: 72) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:reviewer) { create(:user) }
  let(:now) { Time.zone.parse("2026-09-18 09:00") }
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed", payment_status: "pending",
                     total_amount: 1000, currency: "MYR", check_in: now + 60.days, check_out: now + 62.days)
  end
  let!(:folio) { create(:booking_folio, booking: booking, hotel: hotel, currency: "MYR") }

  before { Bookings::CreatePaymentSchedule.call(booking: booking, from: now) }

  # Posts to the folio and syncs, which is how every real payment path settles.
  def pay(amount)
    result = Folios::Transactions::InsertTransaction.new(
      booking_folio: folio, amount: amount, transaction_type: "payment", category: "booking_payment",
      user: reviewer, description: "test payment", options: { system_posting: true, posting_source: "spec" }
    ).call
    raise result.error unless result.success?

    Deposits::SyncBookingPaymentStatus.call(booking.reload, folio_transaction: result.transaction, user: reviewer)
  end

  it "marks the deposit paid and moves the deadline to the balance" do
    pay(500)

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[paid pending])
    expect(booking.payment_status).to eq("partial")
    expect(booking.payment_due_at).to eq(booking.payment_instalments.last.due_at)
    expect(booking.payment_instalments.first).to have_attributes(paid_by_id: reviewer.id)
    expect(booking.payment_instalments.first.payment_folio_transaction).to be_present
  end

  it "clears the deadline once the balance is paid too" do
    pay(500)
    pay(500)

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[paid paid])
    expect(booking.payment_status).to eq("captured")
    expect(booking.payment_due_at).to be_nil
  end

  it "settles both stages when the agent pays everything at once" do
    pay(1000)

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[paid paid])
    expect(booking.payment_due_at).to be_nil
  end

  it "leaves the deposit pending when a payment falls short of it" do
    pay(200)

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[pending pending])
    expect(booking.payment_due_at).to eq(now + 72.hours)
    expect(Bookings::PaymentProgress.new(booking).amount_due_now).to eq(300)
  end

  it "counts a top-up towards a deposit already part paid" do
    pay(200)
    pay(300)

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[paid pending])
  end

  it "counts an overpayment of the deposit towards the balance" do
    pay(700)

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[paid pending])
    expect(Bookings::PaymentProgress.new(booking).amount_due_now).to eq(300)
  end

  it "does not mark a later stage paid ahead of an earlier one" do
    booking.payment_instalments.first.update!(status: "waived")
    booking.payment_instalments.last.update!(amount: 700)

    pay(600)

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[waived pending])
  end

  it "is idempotent" do
    pay(500)

    expect { described_class.call(booking: booking.reload) }.not_to change { booking.reload.payment_instalments.map(&:paid_at) }
  end

  # The desk posts payments straight to the folio too. Without this the stage
  # stayed pending and a booking the agent had paid could be released.
  it "settles a stage when the desk posts the payment directly to the folio" do
    Folios::Transactions::InsertTransaction.new(
      booking_folio: folio, amount: 500, transaction_type: "payment", category: "booking_payment",
      user: reviewer, description: "cash at desk", options: { system_posting: true, posting_source: "desk" }
    ).call

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[paid pending])
    expect(booking.payment_status).to eq("partial")
    expect(booking.payment_due_at).to eq(booking.payment_instalments.last.due_at)
  end

  it "leaves a booking with no schedule alone when a payment is posted to its folio" do
    plain = create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", total_amount: 300, currency: "MYR")
    plain_folio = create(:booking_folio, booking: plain, hotel: hotel, currency: "MYR")

    Folios::Transactions::InsertTransaction.new(
      booking_folio: plain_folio, amount: 100, transaction_type: "payment", category: "booking_payment",
      user: reviewer, description: "cash", options: { system_posting: true, posting_source: "desk" }
    ).call

    expect(plain.reload.payment_status).to eq("pending")
  end

  # A deposit applied to the folio outside a slip used to leave the booking part
  # paid with its deposit stage pending, which the sweeper would then release.
  it "settles the deposit stage when a prepayment is applied to the folio" do
    prepayment = create(:deposit, :prepayment, booking: booking, hotel: hotel, amount: 500, currency: "MYR")

    result = Deposits::Apply.call(deposit: prepayment, booking_folio: folio, amount: 500, operation_key: "settle-1")

    expect(result).to be_success
    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[paid pending])
    expect(booking.payment_status).to eq("partial")
    expect(booking.payment_due_at).to eq(booking.payment_instalments.last.due_at)
  end
end
