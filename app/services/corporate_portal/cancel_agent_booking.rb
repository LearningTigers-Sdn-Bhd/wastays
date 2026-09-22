# frozen_string_literal: true

module CorporatePortal
  # An agent cancelling their own booking from the corporate portal.
  #
  # The booking is not deleted. It becomes `cancelled` and stays on the agent's
  # list and in the hotel's reservations as cancelled history, because a stay
  # that vanishes is a stay nobody can answer questions about later.
  #
  # Inventory is not touched here. Bookings::TransitionStatus already releases it
  # on cancel and writes the BookingAuditLog, so the rooms go back on sale
  # through exactly the path a desk cancellation takes -- one release path, one
  # audit trail, and no second place for the counts to drift.
  #
  # **Only while unpaid.** An agent may undo a booking they have not paid for.
  # Once money is with the hotel -- approved, or a slip sitting in the review
  # queue -- only the hotel can cancel, because only the hotel can decide what
  # happens to the money. Refusing is the safe answer; a refund an agent can
  # trigger themselves is not in scope.
  #
  # A multi-room stay is several bookings under one group, so cancelling one row
  # cancels the whole stay. Releasing three of four rooms would leave the guest
  # with a reservation nobody meant to keep.
  class CancelAgentBooking
    SOURCE = "corporate_portal"
    CANCELLABLE_STATUSES = %w[pending confirmed].freeze
    UNPAID_PAYMENT_STATUSES = %w[pending failed].freeze

    Result = Struct.new(:bookings, :error, keyword_init: true) do
      def success? = error.blank?
    end

    def self.call(...) = new(...).call

    def initialize(booking:, user:, now: Time.current)
      @booking = booking
      @user = user
      @now = now
    end

    def call
      refusal = refusal_reason
      return Result.new(error: refusal) if refusal.present?

      cancel_all
    end

    # Whether the portal should offer a Cancel button at all. The same predicate
    # decides it, so the button is never shown for something the service would
    # then refuse.
    def cancellable?
      refusal_reason.blank?
    end

    def refusal_reason
      return "This booking has already been cancelled." if @booking.status == "cancelled"
      return "This booking can no longer be cancelled here. Please contact the hotel to cancel it." unless CANCELLABLE_STATUSES.include?(@booking.status)
      return "This stay has already started. Please contact the hotel to make any changes." if arrival_passed?
      return "This booking has been paid. Please contact the hotel to arrange a cancellation." unless unpaid?
      return "Your transfer slip is with the hotel for review. They will be in touch once it has been looked at." if submission_under_review?

      nil
    end

    # Every room of the stay, not just the one the agent clicked.
    def group
      @group ||= if @booking.group_booking_id.present?
        Booking.where(
          hotel_corporate_account_id: @booking.hotel_corporate_account_id,
          group_booking_id: @booking.group_booking_id
        ).order(:group_position, :id).to_a
      else
        [ @booking ]
      end
    end

    private

    # Asked of the whole group, because the whole group is what gets cancelled.
    # Rooms in a stay share their dates by construction, but a room paid for on
    # its own must still stop the cancellation -- the guard has to cover
    # everything the service would touch, not only the row that was clicked.
    def arrival_passed?
      group.any? { |booking| booking.check_in.present? && booking.check_in <= @now }
    end

    def unpaid?
      group.all? { |booking| UNPAID_PAYMENT_STATUSES.include?(booking.payment_status) }
    end

    def submission_under_review?
      ArPaymentSubmission.pending.where(booking_id: group.map(&:id)).exists?
    end

    def cancel_all
      cancelled = []
      error = nil

      Booking.transaction do
        group.each do |booking|
          # A room already cancelled is left alone rather than refused: the stay
          # as a whole is still what the agent asked to cancel.
          next if booking.status == "cancelled"

          result = ::Bookings::TransitionStatus.new(
            booking: booking,
            status: "cancelled",
            user: @user,
            options: { source: SOURCE, reason: reason }
          ).call

          unless result.success?
            error = result.error
            raise ActiveRecord::Rollback
          end

          # The rooms are gone; the sweeper has nothing left to release.
          booking.update!(payment_due_at: nil)
          cancelled << booking
        end
      end

      return Result.new(error: error) if error.present?

      Result.new(bookings: cancelled)
    end

    def reason
      "Cancelled by #{@user&.name.presence || 'the agency'} in the corporate portal."
    end
  end
end
