# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::SyncPaymentDeadline do
  let(:hotel) { create(:hotel, status: "live") }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:deposit_due) { Time.zone.parse("2026-09-21 09:00") }
  let(:balance_due) { Time.zone.parse("2026-10-20 23:59") }
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed",
                     payment_status: "pending", total_amount: 1000, payment_due_at: nil)
  end

  def instalment(position, kind, due_at, status: "pending")
    booking.payment_instalments.create!(position: position, kind: kind, amount: 500, due_at: due_at, status: status)
  end

  context "with a schedule" do
    it "points the booking at the earliest pending stage" do
      instalment(1, "deposit", deposit_due)
      instalment(2, "balance", balance_due)

      described_class.call(booking)

      expect(booking.reload.payment_due_at).to eq(deposit_due)
    end

    it "moves on to the next stage once the first is paid" do
      instalment(1, "deposit", deposit_due, status: "paid")
      instalment(2, "balance", balance_due)

      described_class.call(booking)

      expect(booking.reload.payment_due_at).to eq(balance_due)
    end

    it "clears the deadline when no stage is pending" do
      booking.update!(payment_due_at: balance_due)
      instalment(1, "deposit", deposit_due, status: "paid")
      instalment(2, "balance", balance_due, status: "paid")

      described_class.call(booking)

      expect(booking.reload.payment_due_at).to be_nil
    end

    it "ignores a refunded or waived stage" do
      instalment(1, "deposit", deposit_due, status: "refunded")
      instalment(2, "balance", balance_due, status: "waived")

      described_class.call(booking)

      expect(booking.reload.payment_due_at).to be_nil
    end
  end

  context "with no schedule" do
    before { booking.update!(payment_due_at: deposit_due) }

    it "keeps the deadline while the booking is unpaid or only part paid" do
      %w[pending partial].each do |status|
        booking.update!(payment_status: status)
        described_class.call(booking)

        expect(booking.reload.payment_due_at).to eq(deposit_due)
      end
    end

    it "clears the deadline once the booking is paid in full" do
      booking.update!(payment_status: "captured")

      described_class.call(booking)

      expect(booking.reload.payment_due_at).to be_nil
    end
  end
end
