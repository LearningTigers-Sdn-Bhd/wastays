module Refunds
  # Creates or resubmits a guest's refund request.
  #
  # Two modes, because the two surfaces ask two different questions:
  #
  # - :pre_stay is the Guest Portal. A guest cancels a confirmed booking, and
  #   the cancellation policy sets the amount.
  # - :post_stay is the stay page. A guest who already stayed disputes a charge.
  #   The booking status never changes, and the guest names the amount.
  #
  # Either way the record is a request. Staff approves or rejects it in the
  # Hotel Portal, and no money moves here.
  class SubmitRequest
    MODES = %i[pre_stay post_stay].freeze
    NOT_ELIGIBLE = "This booking isn't eligible for a refund request."

    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(booking:, params:, mode: :pre_stay)
      @booking = booking
      @params = params
      @mode = mode.to_sym
      raise ArgumentError, "Unknown refund mode: #{mode}" unless @mode.in?(MODES)
    end

    def call
      return post_stay_submission if post_stay?

      pre_stay_submission
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: invalid_submission_message(e))
    end

    private

    attr_reader :mode

    def post_stay? = mode == :post_stay

    # ---------------------------------------------------------------- pre stay

    def pre_stay_submission
      policy = RefundPolicy.first
      return failure("Refund requests are currently unavailable. Please try again later.") unless policy
      return failure(ineligibility_reason(policy)) unless eligible?(policy)

      refund_amount = (@booking.total_amount * (policy.refund_percentage / 100.0)).round(2)

      ActiveRecord::Base.transaction do
        if resubmit?
          update_request(refund_amount)
        else
          @booking.transition_status_to!("cancelled", event: "cancel")
          create_request(refund_amount)
        end
      end

      success
    end

    # --------------------------------------------------------------- post stay

    def post_stay_submission
      return failure(NOT_ELIGIBLE) unless post_stay_eligible?

      amount = requested_amount
      return failure("Please enter the amount you are asking us to refund.") if amount.blank?
      return failure("Please enter an amount above zero.") unless amount.positive?
      return failure("The amount cannot be more than the #{formatted_total} you paid.") if amount > @booking.total_amount

      ActiveRecord::Base.transaction do
        resubmit? ? update_request(amount) : create_request(amount)
      end

      success
    end

    # The stay page holds the booking, and Concierge::StayAccess::Eligibility
    # already decided that the stay can be seen. The only question left here is
    # whether a request is open already.
    def post_stay_eligible?
      return true if resubmit?

      @booking.refund_request.blank?
    end

    def requested_amount
      raw = @params[:refund_amount]
      return nil if raw.to_s.strip.blank?

      BigDecimal(raw.to_s.strip).round(2)
    rescue ArgumentError
      nil
    end

    def formatted_total
      "#{@booking.currency} #{format('%.2f', @booking.total_amount)}"
    end

    # ------------------------------------------------------------------ shared

    def create_request(refund_amount)
      RefundRequest.create!(request_attributes.merge(booking: @booking, status: "pending", refund_amount: refund_amount))
    end

    def update_request(refund_amount)
      @booking.refund_request.update!(
        request_attributes.merge(hotel_note: nil, status: "pending", refund_amount: refund_amount)
      )
    end

    def request_attributes
      {
        reason: @params[:reason],
        bank_name: @params[:bank_name],
        account_holder_name: @params[:account_holder_name],
        account_number: @params[:account_number],
        account_type: @params[:account_type]
      }
    end

    def resubmit?
      return @booking.refund_request&.rejected? || false if post_stay?

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
      return NOT_ELIGIBLE unless @booking.status == "confirmed"

      days_until_checkin = (@booking.check_in.to_date - Date.current).to_i
      if days_until_checkin < policy.min_days_before_checkin
        "This booking is too close to check-in for an online refund request. Please contact the hotel directly for help."
      elsif @booking.refund_request.present?
        "You already have a refund request for this booking. You can check its status in Refunds."
      else
        NOT_ELIGIBLE
      end
    end

    def success
      Result.new(success?: true, error: nil)
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
