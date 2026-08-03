module Concierge
  class SubmitCheckOutRequest
    def initialize(booking:, guest_notes: nil)
      @booking = booking
      @guest_notes = guest_notes.to_s.strip
    end

    def call
      unless @booking.checked_in?
        return Result.failure(message: "Checkout requests can only be submitted for checked-in bookings.")
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
