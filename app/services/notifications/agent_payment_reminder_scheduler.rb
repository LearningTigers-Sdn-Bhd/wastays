# frozen_string_literal: true

module Notifications
  # Reminds an agent, before the deadline, that rooms they are holding are about
  # to be released.
  #
  # It evaluates the world on every run and sends what is due *now*, rather than
  # queuing mail ahead at booking time. A deadline moves -- a rejected slip
  # extends it, an approval removes it -- and a queue of pre-scheduled reminders
  # would then have to be found and cancelled. Nothing is scheduled ahead, so a
  # booking that gets paid between two runs is simply never picked up again.
  #
  # Which bookings are held, and which have had their clock stopped by a slip
  # already with the hotel, are both answered by Bookings::PaymentHoldScope --
  # the same predicates the sweeper uses, so an agent cannot be cancelled without
  # warning or warned about a booking that was never at risk.
  #
  # **One reminder per run, not the whole series.** With offsets of 24 and 4
  # hours, a booking made three hours before its deadline has passed both
  # windows at once. Sending both would be two identical mails a second apart, so
  # the smallest open offset is sent and the larger ones are recorded as
  # `skipped`: the row still says why nothing went out.
  class AgentPaymentReminderScheduler
    NOTIFICATION_TYPE = "agent_payment_reminder"
    TRIGGER_EVENT = "agent_payment_deadline_approaching"

    Result = Struct.new(:sent, :skipped, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(hotel: nil, now: Time.current)
      @hotel = hotel
      @now = now
    end

    def call
      result = Result.new(sent: [], skipped: [])

      pending_bookings.find_each do |booking|
        config = config_for(booking.hotel_id)
        next unless config&.enabled?
        next if ::Bookings::PaymentHoldScope.protected_by_submission?(booking)

        remind(booking, config, result)
      end

      result
    end

    private

    # Held, and not yet due -- a booking already past its deadline belongs to the
    # sweeper, and a reminder about rooms that are being released as it arrives
    # would be worse than saying nothing.
    def pending_bookings
      scope = ::Bookings::PaymentHoldScope.held.where(payment_due_at: @now...)
      scope = scope.where(hotel: @hotel) if @hotel
      scope.includes(:hotel, :corporate_booked_by, hotel_corporate_account: :corporate_account)
    end

    def config_for(hotel_id)
      @configs ||= NotificationConfig.where(notification_type: NOTIFICATION_TYPE).index_by(&:hotel_id)
      @configs[hotel_id]
    end

    def remind(booking, config, result)
      hours_left = (booking.payment_due_at - @now) / 1.hour
      # Largest first from the config; the last match is the smallest offset
      # whose window is open, which is the one worth sending.
      open_offsets = config.agent_reminder_offsets_hours.select { |offset| hours_left <= offset }
      return if open_offsets.empty?

      due_offset = open_offsets.last

      open_offsets.each do |offset|
        next if offset == due_offset

        # An offset already on file was sent on an earlier run, not passed over
        # now, so it is not counted again.
        result.skipped << [ booking.id, offset ] if record_superseded(booking, offset)
      end

      outcome = QueueAgentPaymentNotice.call(
        booking: booking,
        notification_type: NOTIFICATION_TYPE,
        trigger_event: TRIGGER_EVENT,
        idempotency_key: key_for(booking, due_offset),
        extra: { reminder_offset_hours: due_offset }
      )
      result.sent << [ booking.id, due_offset ] if outcome.sent
    end

    # A skipped delivery rather than nothing at all, so a later run does not
    # reconsider the offset and so the record shows it was deliberately passed
    # over.
    def record_superseded(booking, offset)
      key = key_for(booking, offset)
      return false if NotificationDelivery.exists?(idempotency_key: key)

      NotificationDelivery.create!(
        hotel: booking.hotel,
        booking: booking,
        notification_type: NOTIFICATION_TYPE,
        channel: "email",
        trigger_event: TRIGGER_EVENT,
        idempotency_key: key,
        status: "skipped",
        error_message: "A nearer reminder was due at the same time.",
        payload: { reminder_offset_hours: offset }
      )
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end

    # The deadline is part of the key on purpose. A rejected slip extends
    # payment_due_at, and the agent needs the series again against the new date
    # -- with the old rows still on file saying what they were told before.
    def key_for(booking, offset)
      [ booking.hotel_id, booking.id, NOTIFICATION_TYPE, "email", booking.payment_due_at.to_i, "h#{offset}" ].join(":")
    end
  end
end
