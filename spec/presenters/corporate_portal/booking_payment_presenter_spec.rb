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
    expect(presenter.status_note).to eq("No payment is outstanding on this booking.")
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
      expect(presenter.status_note).to include("deadline is paused")
    end

    it "is not overdue even past the deadline" do
      booking.update!(payment_due_at: 1.hour.ago)

      expect(presenter).not_to be_overdue
    end
  end

  it "is overdue past the deadline with nothing under review" do
    booking.update!(payment_due_at: 1.hour.ago)

    expect(presenter).to be_overdue
    expect(presenter.status_note).to include("keep these rooms")
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

  # The one word both portals' badges are built from, so the desk and the agent
  # can never be shown different answers about the same booking.
  describe "#state and its badge" do
    it "is due, in warning, while the deadline is ahead" do
      expect(presenter.state).to eq(:due)
      expect(presenter.badge_variant).to eq(:warning)
      expect(presenter.badge_label).to start_with("Awaiting payment")
    end

    it "is overdue, in red, once the deadline has passed" do
      booking.update!(payment_due_at: 1.hour.ago)

      expect(presenter.state).to eq(:overdue)
      expect(presenter.badge_label).to eq("Payment past due")
      expect(presenter.badge_variant).to eq(:destructive)
    end

    it "is under review while a slip is with the hotel" do
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking)

      expect(presenter.state).to eq(:under_review)
      expect(presenter.badge_label).to eq("Slip under review")
    end

    it "is paid once nothing is owed" do
      booking.update!(payment_due_at: nil)

      expect(presenter.state).to eq(:paid)
      expect(presenter.badge_variant).to eq(:success)
    end

    # A closed stay stays on the list as history, but should not compete with the
    # bookings that still need paying.
    it "dims a cancelled row so the live ones read first" do
      booking.transition_status_to!("cancelled", event: "cancel")

      expect(presenter).to be_inactive
      expect(presenter.dimmed_class).to eq("opacity-55")
    end

    it "leaves a live row at full weight" do
      expect(presenter).not_to be_inactive
      expect(presenter.dimmed_class).to be_nil
    end

    it "reads as cancelled whatever the money says" do
      booking.transition_status_to!("cancelled", event: "cancel")

      expect(presenter.state).to eq(:cancelled)
      expect(presenter.badge_label).to eq("Cancelled")
    end
  end

  # Rendered server-side so the list still says how long is left with JavaScript
  # off; payment_deadline_controller.js refines it live.
  describe "#time_left_label", frozen_time: :business_day do
    it "counts whole days while more than one is left" do
      booking.update!(payment_due_at: 50.hours.from_now)

      expect(presenter.time_left_label).to eq("2 days left")
      expect(presenter.days_left).to eq(2)
    end

    # Below a day "0 days" reads as "today", which tells the agent nothing.
    it "falls back to hours inside the last day" do
      booking.update!(payment_due_at: 5.hours.from_now)

      expect(presenter.time_left_label).to eq("5 hours left")
    end

    it "falls back to minutes inside the last hour" do
      booking.update!(payment_due_at: 20.minutes.from_now)

      expect(presenter.time_left_label).to eq("20 minutes left")
    end

    it "never says less than a minute is some fraction of one" do
      booking.update!(payment_due_at: 20.seconds.from_now)

      expect(presenter.time_left_label).to eq("1 minute left")
    end

    it "says overdue once the deadline has gone" do
      booking.update!(payment_due_at: 1.minute.ago)

      expect(presenter.time_left_label).to eq("overdue")
      expect(presenter.days_left).to eq(0)
    end
  end

  # A list of fifty bookings would otherwise run two queries a row.
  describe "not querying per row" do
    it "uses submissions it was handed" do
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking)
      preloaded = described_class.new(booking, submissions: [])

      expect(ArPaymentSubmission).not_to receive(:for_booking)
      expect(preloaded).not_to be_under_review
    end

    # The hotel portal builds one presenter per reservation from many different
    # call sites, so it preloads the association rather than passing a list.
    it "uses the association when the caller preloaded it" do
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking)
      preloaded = Booking.includes(:ar_payment_submissions).find(booking.id)

      expect(ArPaymentSubmission).not_to receive(:for_booking)
      expect(described_class.new(preloaded)).to be_under_review
    end

    it "still answers for a booking nobody preloaded" do
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking)

      expect(described_class.new(Booking.find(booking.id))).to be_under_review
    end
  end
end
