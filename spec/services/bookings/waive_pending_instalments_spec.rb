# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::WaivePendingInstalments do
  let(:booking) { create(:booking, status: "cancelled", total_amount: 1000, payment_due_at: 3.days.from_now) }

  def instalment(position, kind, status)
    booking.payment_instalments.create!(position: position, kind: kind, amount: 500, due_at: position.days.from_now, status: status)
  end

  it "waives the stages still owed and clears the booking's deadline" do
    instalment(1, "deposit", "pending")
    instalment(2, "balance", "pending")

    described_class.call(booking)

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[waived waived])
    expect(booking.payment_instalments.map(&:note)).to all(eq("Booking cancelled"))
    expect(booking.payment_due_at).to be_nil
  end

  it "leaves a stage already paid exactly as it was" do
    paid = instalment(1, "deposit", "paid")
    paid.update!(paid_at: 1.day.ago)
    instalment(2, "balance", "pending")

    described_class.call(booking)

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[paid waived])
    expect(paid.reload.note).to be_nil
  end

  it "does nothing for a booking with no schedule" do
    expect { described_class.call(booking) }.not_to raise_error
    expect(booking.reload.payment_due_at).to be_present
  end
end
