module Concierge
  class SubmitGuestRequest
    ALLOWED_KINDS = %w[housekeeping complaint].freeze

    def initialize(booking:, kind:, details:)
      @booking = booking
      @kind = kind.to_s
      @details = details.to_s.strip
    end

    def call
      return Result.failure(message: "Invalid request type.") unless ALLOWED_KINDS.include?(@kind)
      return Result.failure(message: "Details cannot be blank.") if @details.blank?

      unless @booking.status.in?(%w[confirmed checked_in])
        return Result.failure(message: "Requests can only be submitted for active bookings.")
      end

      record = build_request
      if record.save
        Result.success(request: record)
      else
        Result.failure(message: record.errors.full_messages.join(", "))
      end
    end

    private

    def build_request
      meta = { source: "concierge_page" }
      if @kind == "housekeeping"
        @booking.housekeeping_requests.build(
          request_details: @details,
          status: "pending",
          requested_at: Time.current,
          metadata: meta
        )
      else
        @booking.complaint_requests.build(
          complaint_details: @details,
          status: "pending",
          requested_at: Time.current,
          metadata: meta
        )
      end
    end
  end
end
