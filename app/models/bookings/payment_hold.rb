# frozen_string_literal: true

module Bookings
  # How long an agent's booking is held before it must be paid for, and when a
  # given booking therefore falls due.
  #
  # One place decides this, because the answer drives an automated cancellation:
  # the TA portal shows it, the sweeper enforces it, and the two must never
  # disagree about what was promised.
  #
  # Four rules the rest of the app must not re-derive:
  #
  # * **Standard accounts only.** A direct-bill agency is invoiced after the
  #   stay by arrangement; releasing its rooms for non-payment up front would
  #   contradict the arrangement.
  # * **Wall-clock, not the business date.** The business date only moves when
  #   the night audit runs and can sit days behind. A deadline is a promise to a
  #   person about real time.
  # * **Floored at arrival.** A 48-hour hold on a booking arriving tomorrow
  #   cannot run past the arrival it is holding, so it is cut short. The UI has
  #   to say so.
  # * **Never already expired.** An agent booking a room for this afternoon,
  #   after the property's check-in time, would otherwise be handed a deadline
  #   in the past: the floor lands before the booking exists, and the sweeper
  #   cancels it within minutes without the agent ever having had a chance to
  #   pay. The floor is therefore clamped to a minimum. Past arrival the floor's
  #   own promise -- money before the guest walks in -- is already unkeepable,
  #   so nothing is lost by letting the deadline sit slightly beyond it.
  module PaymentHold
    DEFAULT_HOURS = 72

    # The least time an agent can be given, however late the booking is taken.
    # Safe to apply unconditionally: both hold columns are integer hours under a
    # "> 0" check constraint, so the configured hold is never shorter than this
    # and the clamp can only ever lift a deadline the arrival floor pushed down.
    MINIMUM_HOLD = 30.minutes

    module_function

    # nil when this booking is not held for payment at all.
    def due_at(booking:, from: Time.current)
      relationship = booking.hotel_corporate_account
      return unless applies_to?(relationship)

      hours = hours_for(relationship)
      return if hours.blank?

      floored = [ from + hours.hours, booking.check_in ].compact.min
      [ floored, from + MINIMUM_HOLD ].max
    end

    def applies_to?(relationship)
      relationship.present? && relationship.relationship_type_standard?
    end

    # The agency's own hold, else the property's default.
    def hours_for(relationship)
      relationship.agent_payment_hold_hours.presence ||
        relationship.hotel&.agent_payment_hold_hours.presence ||
        DEFAULT_HOURS
    end

    # True when the deadline had to be cut short by the arrival date, which is
    # the case the agent will otherwise read as an error.
    def floored_at_arrival?(booking:, from: Time.current)
      return false if booking.check_in.blank?

      relationship = booking.hotel_corporate_account
      return false unless applies_to?(relationship)

      hours = hours_for(relationship)
      hours.present? && (from + hours.hours) > booking.check_in
    end

    # Taken at or after the arrival it is holding -- a room sold for this
    # afternoon once the desk is already checking guests in. The hold is the
    # minimum rather than the configured one, and the agent has to be told why
    # their hour became half of one.
    def booked_after_arrival?(booking:, from: Time.current)
      return false if booking.check_in.blank?
      return false unless applies_to?(booking.hotel_corporate_account)

      booking.check_in <= from
    end
  end
end
