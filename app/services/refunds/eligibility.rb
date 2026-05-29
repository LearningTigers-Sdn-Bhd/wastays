# frozen_string_literal: true

module Refunds
  class Eligibility
    Result = Struct.new(:success?, :error, :policy, :suggested_amount, keyword_init: true)

    def initialize(booking)
      @booking = booking
    end

    def call
      policy = RefundPolicy.first
      return failure("Refund requests are currently unavailable (no policy defined).") unless policy
      return failure("This is a manual booking. Only online bookings are eligible for platform refunds.") unless @booking.online?
      return failure("A refund request already exists for this booking.") if @booking.refund_request.present?

      unless @booking.status.in?(%w[confirmed cancelled])
        return failure("Booking must be confirmed or cancelled to initiate a refund.")
      end

      # For cancelled bookings, we use the updated_at as an approximation of cancellation time 
      # if we don't have a specific cancelled_at timestamp.
      reference_date = (@booking.status == "cancelled") ? @booking.updated_at.to_date : Date.current
      days_until_checkin = (@booking.check_in.to_date - reference_date).to_i

      if days_until_checkin < policy.min_days_before_checkin
        return failure("The refund policy was not followed. It was cancelled only #{days_until_checkin} days before check-in, but the policy requires at least #{policy.min_days_before_checkin} days.")
      end

      refund_amount = (@booking.total_amount * (policy.refund_percentage / 100.0)).round(2)

      Result.new(
        success?: true,
        policy: policy,
        suggested_amount: refund_amount
      )
    end

    private

    def failure(message)
      Result.new(success?: false, error: message)
    end
  end
end
