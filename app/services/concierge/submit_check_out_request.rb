module Concierge
  class SubmitCheckOutRequest
    def initialize(booking:, guest_notes: nil)
      @booking = booking
      @guest_notes = guest_notes.to_s.strip
    end

    def call
      # Every in-house status can ask to check out, not only checked_in. A guest
      # whose booking is already due out or past its checkout time is exactly
      # the guest who needs this.
      unless @booking.status.in?(Booking::IN_HOUSE_STATUSES)
        return Result.failure(message: "Checkout requests are for guests who are still in house.")
      end

      if @booking.check_out_requests.open_tasks.exists?
        return Result.failure(message: "A checkout request is already pending for this booking.")
      end

      request = @booking.check_out_requests.create!(
        status: "new",
        requested_at: Time.current,
        guest_notes: @guest_notes.presence
      )

      Result.success(check_out_request: request)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(message: e.message)
    end
  end
end
