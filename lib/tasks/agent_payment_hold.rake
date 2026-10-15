# frozen_string_literal: true

namespace :agent_payment_hold do
  desc "Stamp a payment deadline onto agent bookings that predate the payment " \
       "hold feature, so the sweeper and reminder scheduler start picking them up"
  task backfill_payment_due_at: :environment do
    # Deliberately anchored to "now", not to when each booking was made. These
    # bookings have been held, unpaid, for however long they have already
    # existed without anyone chasing them for it -- reusing Bookings::PaymentHold
    # with the booking's own creation time as `from` would hand some of them a
    # deadline already in the past and cancel them the moment this task runs,
    # with no warning ever sent. Anchoring to now gives every one of them a
    # fresh, full window from this point, which is the non-disruptive choice
    # for a first run. Running the task again is a no-op: only bookings still
    # missing a deadline are touched.
    scope = Booking
      .where(status: "confirmed", payment_status: %w[pending failed])
      .where(payment_due_at: nil)
      .where.not(hotel_corporate_account_id: nil)

    stamped = 0
    skipped = 0

    scope.includes(:hotel_corporate_account).find_each do |booking|
      due_at = Bookings::PaymentHold.due_at(booking: booking)

      if due_at.blank?
        skipped += 1
        next
      end

      booking.update!(payment_due_at: due_at)
      stamped += 1
    end

    puts "Stamped payment_due_at on #{stamped} agent booking(s); " \
         "#{skipped} left alone (direct-bill or otherwise not held)."
  end
end
