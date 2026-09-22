# frozen_string_literal: true

module CorporatePortal
  # What an agent needs to know about paying for one booking: how much, by when,
  # and whether anything is already with the hotel.
  #
  # The deadline is stated in the hotel's timezone and named as such, because
  # the agent is often not in it and "by 2pm Friday" is ambiguous otherwise.
  #
  # The hotel portal reads the same presenter for the badge on a reservation, so
  # the desk and the agent can never be shown different answers about whether a
  # booking is paid.
  #
  # `submissions:` takes an already-loaded list for this booking. A list of 50
  # bookings would otherwise run two queries per row.
  class BookingPaymentPresenter
    BADGE_VARIANTS = {
      paid: :success,
      under_review: :info,
      overdue: :destructive,
      in_house: :warning,
      due: :warning,
      cancelled: :neutral
    }.freeze

    def initialize(booking, submissions: nil, now: Time.current)
      @booking = booking
      @submissions = submissions
      @now = now
    end

    attr_reader :booking, :now

    def due_at = booking.payment_due_at

    # Follows the money, not the inventory. A checked-in booking is out of the
    # sweeper's reach (Bookings::PaymentHoldScope) but the agency still owes for
    # it, and saying otherwise is how an unpaid stay used to reach the checkout
    # counter with both portals insisting it was paid.
    def awaiting_payment?
      due_at.present? && booking.status.in?(::Bookings::PaymentHoldScope::SETTLING_STATUSES) && unpaid?
    end

    # The guest is in the room and the bill is still open. The rooms are no
    # longer at risk, so this is not a deadline any more -- it is a debt, and the
    # desk is the one who will meet it.
    def in_house?
      awaiting_payment? && booking.status.in?(::Bookings::PaymentHoldScope::IN_HOUSE_STATUSES)
    end

    def unpaid?
      booking.payment_status.in?(%w[pending failed])
    end

    # A slip is with the hotel and has not been looked at yet. While this is
    # true the clock is stopped and the rooms are not at risk.
    def submission_under_review
      @submission_under_review ||= submissions.select { |s| s.status == "pending" }.max_by(&:created_at)
    end

    def under_review? = submission_under_review.present?

    def rejected_submission
      @rejected_submission ||= submissions.select { |s| s.status == "rejected" }.max_by { |s| s.reviewed_at || s.created_at }
    end

    def overdue?
      awaiting_payment? && !under_review? && !in_house? && due_at <= now
    end

    def closed? = booking.closed?

    # The one word for this booking's money, used by both portals' badges.
    #
    # A closed booking is checked for a pending submission before it is
    # checked for closure: the hotel can void or cancel a booking without
    # first resolving a slip that is sitting in its review queue, and that
    # must not read as "Paid" -- the money has not actually been looked at.
    # Off that one exception, a closed booking's payment state does not matter
    # otherwise; closed always wins over paid, overdue, or awaiting payment.
    def state
      return :under_review if closed? && under_review?
      return :cancelled if closed?
      return :paid unless awaiting_payment?
      return :under_review if under_review?
      return :in_house if in_house?
      return :overdue if overdue?

      :due
    end

    def badge_variant = BADGE_VARIANTS.fetch(state, :neutral)

    # The `data-state` the deadline panel styles itself from.
    # payment_deadline_controller.js overwrites it with "urgent"/"overdue" as the
    # clock runs, but only where there is a clock to run.
    def deadline_state
      return "in-house" if in_house?
      return "review" if under_review?

      "pending"
    end

    def badge_label
      case state
      when :cancelled then booking.status == "voided" ? "Voided" : "Cancelled"
      when :paid then "Paid"
      when :under_review then "Slip under review"
      when :in_house then "Unpaid · guest in house"
      when :overdue then "Payment past due"
      else [ "Awaiting payment", time_left_label ].compact.join(" · ")
      end
    end

    # A cancelled or voided stay is closed: the rooms are back on sale and
    # there is nothing for the agent to do -- even if a stray submission is
    # still sitting in review (see `state`). It stays on the list as history,
    # but recedes so the bookings that still need paying read first.
    def inactive? = closed?

    def dimmed_class = ("opacity-55" if inactive?)

    def amount_label
      "#{booking.currency} #{ActiveSupport::NumberHelper.number_to_rounded(booking.total_amount, precision: 2, delimiter: ',')}"
    end

    # Spelled out with the zone, because the agent may not be in the hotel's.
    # The time reads "11.03am", not "11:03" -- a period and a lowercase
    # am/pm, the way a person says a time rather than how a clock displays one.
    def due_at_label
      return if due_at.blank?

      due_at.in_time_zone(time_zone).strftime("%d %b %Y, %-l.%M%P %Z")
    end

    # Whole days remaining, wall-clock, once at least a day is left. Below that
    # the number of days is always "0", which reads as "today" and tells the
    # agent nothing, so it falls back to hours and then minutes.
    #
    # Rendered server-side so the list still says how long is left with
    # JavaScript off; payment_deadline_controller.js refines it live.
    def days_left
      return if due_at.blank?

      seconds = due_at - now
      return 0 if seconds.negative?

      (seconds / 1.day).floor
    end

    def time_left_label
      return if due_at.blank?

      seconds = (due_at - now).to_i
      return "overdue" if seconds <= 0
      return "#{pluralized(seconds / 1.day, 'day')} left" if seconds >= 1.day
      return "#{pluralized(seconds / 1.hour, 'hour')} left" if seconds >= 1.hour

      "#{pluralized([ seconds / 1.minute, 1 ].max, 'minute')} left"
    end

    # A hold that would have run past arrival is cut short at it. An agent who
    # is told "48 hours" and sees less needs to be told why.
    #
    # Asked of Bookings::PaymentHold against the moment the hold started rather
    # than compared to the stored deadline: the deadline is clamped to a minimum
    # when arrival is close, so it no longer equals check_in in exactly the cases
    # that most need explaining. Recomputing from `now` would be worse still --
    # every booking arriving inside the hold window would claim to have been cut
    # short, however long ago it was actually taken.
    def floored_at_arrival?
      return false if due_at.blank? || hold_started_at.blank?

      ::Bookings::PaymentHold.floored_at_arrival?(booking: booking, from: hold_started_at)
    end

    # Sold after the desk was already checking guests in. The hold is the
    # minimum rather than the configured one, and an agent who set an hour and
    # sees thirty minutes is owed the reason.
    def booked_after_arrival?
      return false if hold_started_at.blank?

      ::Bookings::PaymentHold.booked_after_arrival?(booking: booking, from: hold_started_at)
    end

    # When the clock started. `corporate_booked_at` is stamped by
    # CorporatePortal::CreateAgentBooking in the same breath as the deadline, so
    # the two describe the same moment; `created_at` covers a booking that
    # acquired an agency some other way.
    def hold_started_at = booking.corporate_booked_at || booking.created_at

    # Written to read as a service message rather than a warning: it leads with
    # what is being held for the agent and what they can do, and states the
    # release as the policy it is rather than a consequence aimed at them. An
    # agent reading this is a customer, and a deadline they are already meeting
    # should not feel like a threat.
    def status_note
      return "No payment is outstanding on this booking." unless awaiting_payment?
      return "Your transfer slip is with the hotel for review. Your deadline is paused until they respond." if under_review?
      return "The guest has checked in. Settle this booking with the hotel before they check out." if in_house?
      return "This booking is past its payment deadline. Send your transfer slip or contact the hotel to keep these rooms." if overdue?
      return "The guest can arrive at any time from now, so this booking has a short hold rather than the usual one." if booked_after_arrival?
      return "These rooms arrive soon, so the deadline falls on the arrival date rather than the usual hold." if floored_at_arrival?

      "These rooms are held for you until the deadline above. Send your transfer slip any time before then."
    end

    def time_zone = booking.hotel.hotel_time_zone

    private

    # A caller that preloaded `booking.ar_payment_submissions` -- a list of
    # reservations rendering the agent badge, say -- gets no query at all. The
    # single-booking callers, which are most of them, still get one.
    def submissions
      @submissions ||= if booking.association(:ar_payment_submissions).loaded?
        booking.ar_payment_submissions.to_a
      else
        ArPaymentSubmission.for_booking(booking).to_a
      end
    end

    def pluralized(count, noun)
      "#{count} #{count == 1 ? noun : noun.pluralize}"
    end
  end
end
