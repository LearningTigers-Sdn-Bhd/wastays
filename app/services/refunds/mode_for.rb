# frozen_string_literal: true

module Refunds
  # Which refund a booking can ask for now, if any.
  #
  # - :pre_stay: a confirmed booking inside the policy window, or a cancelled
  #   one whose request was rejected. Asking cancels the booking.
  # - :post_stay: a guest in house, or inside the check-out grace period, with
  #   no open request. Asking does not touch the booking; the guest names the
  #   amount and the property replies.
  # - nil: neither.
  #
  # The Guest Portal reads this to pick its form and its booking card. The
  # stay page is post-stay by definition and does not need to ask.
  class ModeFor
    def initialize(booking:, policy: RefundPolicy.first, now: Time.current)
      @booking = booking
      @policy = policy
      @now = now
    end

    def call
      return :pre_stay if pre_stay?
      return :post_stay if post_stay?

      nil
    end

    private

    def pre_stay?
      return true if @booking.status == "cancelled" && request&.rejected?

      @booking.eligible_for_refund?(@policy)
    end

    def post_stay?
      return false unless request.nil? || request.rejected?

      Concierge::StayAccess::Eligibility.new(booking: @booking, now: @now).call.success?
    end

    def request = @booking.refund_request
  end
end
