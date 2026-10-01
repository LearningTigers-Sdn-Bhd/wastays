# frozen_string_literal: true

module Bookings
  # What a standard travel agent owes on a booking, and by when.
  #
  # The hotel's terms are a deposit within the payment hold and everything paid
  # a set number of days before arrival. A booking made too close to arrival for
  # both to fit is due in full within the hold instead: the deposit deadline is
  # the only one that can still be met.
  #
  # Pure calculation, so the same answer serves the booking screen, the
  # instalments written at creation, and the specs. It never reads what has been
  # paid; that is the folio's business.
  #
  # Deadlines follow Bookings::PaymentHold: wall-clock, floored at arrival, and
  # never already past. The balance is due at the end of the property's calendar
  # day, so "30 days before arrival" means that whole day and does not depend on
  # what time the agent books.
  module PaymentSchedule
    Stage = Data.define(:position, :kind, :amount, :due_at)

    module_function

    # Empty when this booking carries no schedule (direct bill, no agency).
    def for(booking:, from: Time.current)
      relationship = booking.hotel_corporate_account
      return [] unless PaymentHold.applies_to?(relationship)

      total = booking.total_amount.to_d
      deposit_due = PaymentHold.due_at(booking: booking, from: from)
      return [] if total <= 0 || deposit_due.blank?

      hotel = relationship.hotel
      deposit = deposit_amount(total, hotel.agent_deposit_percentage)
      balance_due = balance_due_at(booking, hotel)

      if single_stage?(deposit_due, balance_due, deposit, total, hotel)
        [ Stage.new(position: 1, kind: "full", amount: total, due_at: deposit_due) ]
      else
        [
          Stage.new(position: 1, kind: "deposit", amount: deposit, due_at: deposit_due),
          Stage.new(position: 2, kind: "balance", amount: total - deposit, due_at: balance_due)
        ]
      end
    end

    # Two payments on the same calendar day is one payment with extra steps, so
    # a balance falling on or before the day the deposit is due collapses into it.
    def single_stage?(deposit_due, balance_due, deposit, total, hotel)
      return true if balance_due.nil? || deposit >= total

      balance_due.to_date <= deposit_due.in_time_zone(hotel.hotel_time_zone).to_date
    end

    # Rounded up to the cent, so the deposit is never less than the share promised.
    def deposit_amount(total, percentage)
      (total * percentage / 100).ceil(2)
    end

    def balance_due_at(booking, hotel)
      return if booking.check_in.blank?

      zone = hotel.hotel_time_zone
      due_date = booking.check_in.in_time_zone(zone).to_date - hotel.agent_full_payment_days_before_arrival
      zone.local(due_date.year, due_date.month, due_date.day).end_of_day
    end
  end
end
