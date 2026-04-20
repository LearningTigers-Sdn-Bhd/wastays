module Refunds
  class SubmitRequest
    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(booking:, params:)
      @booking = booking
      @params = params
    end

    def call
      policy = RefundPolicy.first
      return failure("Refund requests are currently unavailable. Please try again later.") unless policy
      return failure(ineligibility_reason(policy)) unless eligible?(policy)

      refund_amount = (@booking.total_amount * (policy.refund_percentage / 100.0)).round(2)

      ActiveRecord::Base.transaction do
        if resubmit?
          @booking.refund_request.update!(
            reason: @params[:reason],
            bank_name: @params[:bank_name],
            account_holder_name: @params[:account_holder_name],
            account_number: @params[:account_number],
            account_type: @params[:account_type],
            hotel_note: nil,
            status: "pending",
            refund_amount: refund_amount
          )
        else
          @booking.update!(status: "cancelled")
          RefundRequest.create!(
            booking: @booking,
            reason: @params[:reason],
            bank_name: @params[:bank_name],
            account_holder_name: @params[:account_holder_name],
            account_number: @params[:account_number],
            account_type: @params[:account_type],
            status: "pending",
            refund_amount: refund_amount
          )
        end
      end

      Result.new(success?: true, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: invalid_submission_message(e))
    end

    private

    def resubmit?
      @booking.status == "cancelled" && @booking.refund_request&.rejected?
    end

    def eligible?(policy)
      return true if resubmit?
      return false unless @booking.status == "confirmed"
      return false if @booking.refund_request.present?

      days_until_checkin = (@booking.check_in.to_date - Date.current).to_i
      days_until_checkin >= policy.min_days_before_checkin
    end

    def ineligibility_reason(policy)
      if @booking.status == "confirmed"
        days_until_checkin = (@booking.check_in.to_date - Date.current).to_i
        if days_until_checkin < policy.min_days_before_checkin
          "This booking is too close to check-in for an online refund request. Please contact the hotel directly for help."
        elsif @booking.refund_request.present?
          "You already have a refund request for this booking. You can check its status in Refunds."
        else
          "This booking isn't eligible for a refund request."
        end
      else
        "This booking isn't eligible for a refund request."
      end
    end

    def failure(message)
      Result.new(success?: false, error: message)
    end

    def invalid_submission_message(error)
      return "Please complete your bank details before submitting your refund request." if bank_details_missing?(error)

      "We couldn't submit your refund request right now. Please check your details and try again."
    end

    def bank_details_missing?(error)
      record = error.record
      return false unless record.is_a?(RefundRequest)

      required_bank_fields = %i[bank_name account_holder_name account_number account_type]
      required_bank_fields.any? { |field| record.errors.added?(field, :blank) }
    end
  end
end
