# frozen_string_literal: true

module CorporatePortal
  # What an agent needs to know about paying for one booking: how much, by when,
  # and whether anything is already with the hotel.
  #
  # The deadline is stated in the hotel's timezone and named as such, because
  # the agent is often not in it and "by 2pm Friday" is ambiguous otherwise.
  class BookingPaymentPresenter
    def initialize(booking)
      @booking = booking
    end

    attr_reader :booking

    def due_at = booking.payment_due_at

    def awaiting_payment?
      due_at.present? && booking.status == "confirmed" && unpaid?
    end

    def unpaid?
      booking.payment_status.in?(%w[pending failed])
    end

    # A slip is with the hotel and has not been looked at yet. While this is
    # true the clock is stopped and the rooms are not at risk.
    def submission_under_review
      @submission_under_review ||= ArPaymentSubmission.pending.for_booking(booking).order(:created_at).last
    end

    def under_review? = submission_under_review.present?

    def rejected_submission
      @rejected_submission ||= ArPaymentSubmission.where(booking: booking, status: "rejected").order(:reviewed_at).last
    end

    def overdue?
      awaiting_payment? && !under_review? && due_at <= Time.current
    end

    def amount_label
      "#{booking.currency} #{ActiveSupport::NumberHelper.number_to_rounded(booking.total_amount, precision: 2, delimiter: ',')}"
    end

    # Spelled out with the zone, because the agent may not be in the hotel's.
    def due_at_label
      return if due_at.blank?

      due_at.in_time_zone(time_zone).strftime("%d %b %Y, %H:%M %Z")
    end

    # A hold that would have run past arrival is cut short at it. An agent who
    # is told "48 hours" and sees less needs to be told why.
    def floored_at_arrival?
      return false if due_at.blank?

      due_at == booking.check_in
    end

    def status_note
      return "Payment received." unless awaiting_payment?
      return "Your transfer slip is with the hotel. The deadline is paused until they review it." if under_review?
      return "This booking is past its payment deadline and the rooms may be released." if overdue?
      return "The deadline is the arrival date, so it is sooner than the usual hold." if floored_at_arrival?

      "Pay by the deadline or the rooms are released."
    end

    def time_zone = booking.hotel.hotel_time_zone
  end
end
