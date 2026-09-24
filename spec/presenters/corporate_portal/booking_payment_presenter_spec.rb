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
    expect(presenter.due_at_label).to eq(booking.payment_due_at.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y, %-l.%M%P %Z"))
    expect(presenter.due_at_label).to match(/\+08\z/)
  end

  # "11.03am", not "11:03" -- read as a spoken time, not a 24-hour clock.
  it "spells the time with a period and a lowercase am/pm, not a 24-hour clock" do
    booking.update!(payment_due_at: ActiveSupport::TimeZone["Asia/Kuala_Lumpur"].parse("2026-09-22 11:03"))
    expect(presenter.due_at_label).to include("11.03am")
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

  # check_in is set explicitly rather than left to the factory, which puts it at
  # today's check-in time: whether that is ahead of or behind Time.current
  # decides which of the two arrival messages applies, and the example would
  # otherwise change meaning at 3pm.
  # The deadline is still cut short -- the predicate says so, and callers use it
  # -- but the note no longer remarks on it. The shortened date is already on
  # screen above the note, and the agent's instruction is the same either way.
  it "says nothing extra about a deadline cut short by the arrival date" do
    booking.update!(check_in: 6.hours.from_now, check_out: 2.days.from_now,
                    payment_due_at: 6.hours.from_now)

    expect(presenter).to be_floored_at_arrival
    expect(presenter).not_to be_booked_after_arrival
    expect(presenter.status_note).to include("held for you until the deadline above")
  end

  # The case that used to read "Payment past due" the instant it was made: an
  # agent selling a room this afternoon, after the desk started checking guests
  # in. The hold is real but short, and the agent is told why.
  it "explains the short hold on a booking taken after arrival" do
    booking.update!(check_in: 1.hour.ago, payment_due_at: 29.minutes.from_now)

    expect(presenter).to be_booked_after_arrival
    expect(presenter).not_to be_overdue
    expect(presenter.state).to eq(:due)
    expect(presenter.status_note).to include("arrive at any time")
  end

  # A booking taken weeks ago, arriving within the hold window, was never cut
  # short by anything and must not claim it was.
  it "does not call an advance booking cut short just because arrival is near" do
    booking.update!(check_in: 6.hours.from_now, check_out: 2.days.from_now,
                    corporate_booked_at: 30.days.ago, created_at: 30.days.ago)

    expect(presenter).not_to be_floored_at_arrival
  end

  # Check-in takes the rooms out of the sweeper's reach, but not the bill out of
  # the agency's hands. Both portals read this presenter, so going quiet here is
  # what sent an unpaid stay to the checkout counter marked "Paid".
  describe "once the guest has checked in unpaid" do
    before do
      booking.update!(payment_due_at: 1.hour.ago)
      booking.transition_status_to!("checked_in", event: "check_in")
    end

    it "still reports the booking as owing" do
      expect(presenter).to be_awaiting_payment
      expect(presenter).to be_in_house
    end

    it "does not call the rooms overdue, because they are no longer at risk" do
      expect(presenter).not_to be_overdue
      expect(presenter.state).to eq(:in_house)
      expect(presenter.badge_label).to eq("Unpaid · guest in house")
      expect(presenter.badge_variant).to eq(:warning)
    end

    it "tells the agent the debt outlives the deadline" do
      expect(presenter.status_note).to eq("The guest has checked in. Settle this booking with the hotel before they check out.")
    end

    it "drops the countdown, which has nothing left to count" do
      expect(presenter.deadline_state).to eq("in-house")
    end

    it "still defers to a slip already with the hotel" do
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking)

      expect(presenter.state).to eq(:under_review)
    end

    it "reads as paid once the money arrives" do
      booking.update!(payment_status: "captured")

      expect(presenter.state).to eq(:paid)
      expect(presenter).not_to be_in_house
    end
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

    # A voided booking releases inventory the same way a cancelled one does
    # (Bookings::VoidBooking) but was not caught by the same check, so it fell
    # through to the "paid" fallback -- an agent whose booking was voided
    # while genuinely unpaid saw a "Paid" badge.
    it "reads as voided, not paid, whatever the money says" do
      booking.transition_status_to!("voided", event: "void")

      expect(presenter.state).to eq(:cancelled)
      expect(presenter.badge_label).to eq("Voided")
      expect(presenter).to be_inactive
    end

    # The hotel can void or cancel a booking without first resolving a slip
    # sitting in its review queue. That must not read as settled -- the money
    # has not actually been looked at -- so the closed status does not win
    # over a submission still waiting on the hotel.
    it "still says a slip is under review even once the booking is voided" do
      booking.transition_status_to!("voided", event: "void")
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking)

      expect(presenter.state).to eq(:under_review)
      expect(presenter.badge_label).to eq("Slip under review")
      # Still recedes in a list: the booking itself is over even though its
      # money is not yet resolved.
      expect(presenter).to be_inactive
    end

    it "does the same for a cancelled booking with a slip still under review" do
      booking.transition_status_to!("cancelled", event: "cancel")
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking)

      expect(presenter.state).to eq(:under_review)
      expect(presenter.badge_label).to eq("Slip under review")
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
