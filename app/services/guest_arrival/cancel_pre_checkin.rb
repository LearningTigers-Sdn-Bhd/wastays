require "ostruct"

module GuestArrival
  class CancelPreCheckin
    def initialize(booking:, pre_checkin:)
      @booking = booking
      @pre_checkin = pre_checkin
    end

    def call
      return OpenStruct.new(success?: false, message: "Completed pre-check-in cannot be cancelled.") if @pre_checkin.completed?

      @pre_checkin.update!(
        status: "pending",
        completed_at: nil,
        document_status: "pending",
        signature_status: "pending"
      )
      @booking.update!(pre_checkin_status: "pending")

      OpenStruct.new(success?: true)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      OpenStruct.new(success?: false, message: e.message)
    rescue => e
      OpenStruct.new(success?: false, message: "Pre-check-in cancellation failed: #{e.message}")
    end
  end
end
