# frozen_string_literal: true

module Bookings
  # Writes a standard agent booking's payment schedule when the booking is taken
  # and points its deadline at the first stage.
  #
  # The schedule is a snapshot of the hotel's terms at this moment, so changing
  # the terms later never rewrites what an agent was promised. Idempotent: a
  # booking that already has a schedule is left alone.
  class CreatePaymentSchedule
    def self.call(...) = new(...).call

    def initialize(booking:, from: Time.current)
      @booking = booking
      @from = from
    end

    def call
      return [] if @booking.payment_instalments.exists?

      stages = PaymentSchedule.for(booking: @booking, from: @from)
      return [] if stages.empty?

      instalments = stages.map do |stage|
        @booking.payment_instalments.create!(
          position: stage.position, kind: stage.kind, amount: stage.amount, due_at: stage.due_at
        )
      end
      SyncPaymentDeadline.call(@booking)
      instalments
    end
  end
end
