# frozen_string_literal: true

module Bookings
  # How long an agent's booking is held before it must be paid for, and when a
  # given booking therefore falls due.
  #
  # One place decides this, because the answer drives an automated cancellation:
  # the TA portal shows it, the sweeper enforces it, and the two must never
  # disagree about what was promised.
  #
  # Three rules the rest of the app must not re-derive:
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
  module PaymentHold
    DEFAULT_HOURS = 48

    module_function

    # nil when this booking is not held for payment at all.
    def due_at(booking:, from: Time.current)
      relationship = booking.hotel_corporate_account
      return unless applies_to?(relationship)

      hours = hours_for(relationship)
      return if hours.blank?

      [ from + hours.hours, booking.check_in ].compact.min
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
  end
end
