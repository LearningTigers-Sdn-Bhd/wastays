# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::BookingPaymentPresenter do
  subject(:presenter) { described_class.new(booking) }

  let(:hotel) { create(:hotel, status: "live", time_zone: "Asia/Kuala_Lumpur") }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed",
                     payment_status: "pending", payment_due_at: 2.days.from_now,
                     total_amount: 1234.5, currency: "MYR")
  end

  it "reports a confirmed, unpaid booking with a deadline as awaiting payment" do
    expect(presenter).to be_awaiting_payment
  end

  it "is not awaiting payment once it has been paid" do
    booking.update!(payment_status: "captured")

    expect(presenter).not_to be_awaiting_payment
    expect(presenter.status_note).to eq("Payment received.")
  end

  it "is not awaiting payment when there is no deadline" do
    booking.update!(payment_due_at: nil)

    expect(presenter).not_to be_awaiting_payment
  end

  it "formats the amount with its currency" do
    expect(presenter.amount_label).to eq("MYR 1,234.50")
  end

  # The agent may not be in the hotel's timezone, so "by 2pm Friday" is
  # ambiguous unless the zone is named.
  it "states the deadline in the hotel's timezone, naming it" do
    expect(presenter.due_at_label).to eq(booking.payment_due_at.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y, %H:%M %Z"))
    expect(presenter.due_at_label).to match(/\+08\z/)
  end

  describe "while a slip is with the hotel" do
    before { create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking) }

    it "reports the clock as paused rather than running" do
      expect(presenter).to be_under_review
      expect(presenter.status_note).to include("paused until they review it")
    end

    it "is not overdue even past the deadline" do
      booking.update!(payment_due_at: 1.hour.ago)

      expect(presenter).not_to be_overdue
    end
  end

  it "is overdue past the deadline with nothing under review" do
    booking.update!(payment_due_at: 1.hour.ago)

    expect(presenter).to be_overdue
    expect(presenter.status_note).to include("may be released")
  end

  it "surfaces why a previous slip was rejected" do
    submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking)
    submission.reject!(reason: "Amount did not match", reviewed_by: create(:user))

    expect(presenter.rejected_submission.rejection_reason).to eq("Amount did not match")
  end

  it "explains a deadline that was cut short by the arrival date" do
    booking.update!(payment_due_at: booking.check_in)

    expect(presenter).to be_floored_at_arrival
    expect(presenter.status_note).to include("arrival date")
  end
end
