# frozen_string_literal: true

module Bookings
  # Where an agent booking stands against its payment schedule: how much has been
  # paid, and what is owed now.
  #
  # The folio is the ledger, so "paid" is read from folio payments (refunds post
  # as negative payments, so the figure is net). Instalments say which stage each
  # payment settled; they are never summed as money received.
  #
  # Amounts owed are cumulative. Paying 100% up front covers both stages, and a
  # payment larger than the deposit reduces the balance, so a stage is met when
  # the net paid reaches the total of every stage up to and including it.
  class PaymentProgress
    def initialize(booking)
      @booking = booking
    end

    # Net of refunds.
    def paid_total
      @paid_total ||= @booking.booking_folios.joins(:folio_transactions)
        .where(folio_transactions: { transaction_type: "payment" })
        .sum("folio_transactions.amount")
    end

    def owed_total
      [ @booking.total_amount.to_d - paid_total, 0 ].max
    end

    def instalments
      @instalments ||= @booking.payment_instalments.to_a
    end

    def scheduled?
      instalments.any?
    end

    def next_instalment
      instalments.find(&:status_pending?)
    end

    # What the agent should send now: the outstanding part of the next stage, or
    # everything owed for a booking with no schedule. Nil when nothing is due.
    def amount_due_now
      return (owed_total if owed_total.positive?) unless scheduled?

      stage = next_instalment
      return if stage.nil?

      due = [ required_through(stage) - paid_total, owed_total ].min
      due if due.positive?
    end

    # Why a slip for this amount cannot be accepted, or nil when it fits: at least
    # the next stage still owed, and no more than is owed in total. Without it an
    # agent's deposit was filed as the full amount, and approving it marked the
    # whole booking paid.
    def amount_problem(amount, currency: @booking.currency)
      return if amount.blank?

      if amount.to_d > owed_total
        "is more than the #{currency} #{format('%.2f', owed_total)} still owed on this booking"
      elsif (due = amount_due_now) && amount.to_d < due
        "must be at least #{currency} #{format('%.2f', due)}, the amount due now"
      end
    end

    # True when the net paid covers every stage up to and including this one.
    def covers?(instalment)
      paid_total >= required_through(instalment)
    end

    private

    # Waived and refunded stages are not owed, so they add nothing to the total
    # the agent has to have paid by then.
    def required_through(instalment)
      instalments
        .select { |stage| stage.position <= instalment.position && !stage.status_refunded? && !stage.status_waived? }
        .sum(&:amount)
    end
  end
end
