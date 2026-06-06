require "ostruct"

module GuestArrival
  class StartPreCheckin
    def initialize(booking)
      @booking = booking
    end

    def call
      return OpenStruct.new(success?: true, pre_checkin: @booking.pre_checkin) if @booking.pre_checkin

      @booking.with_lock do
        @booking.reload
        return OpenStruct.new(success?: true, pre_checkin: @booking.pre_checkin) if @booking.pre_checkin

        pre_checkin = @booking.create_pre_checkin!(
          status: "pending",
          document_status: "pending",
          signature_status: "pending"
        )

        @booking.update!(pre_checkin_status: "pending")

        # Trigger external communication workflows (e.g., WhatsApp)
        # GuestArrival::TriggerWorkflowJob.perform_later(@booking.id, 'pre_checkin_start')
        OpenStruct.new(success?: true, pre_checkin: pre_checkin)
      end
    rescue ActiveRecord::RecordNotUnique
      @booking.reload
      pre_checkin = @booking.pre_checkin
      return OpenStruct.new(success?: true, pre_checkin: pre_checkin) if pre_checkin

      OpenStruct.new(success?: false, message: "Failed to start pre-checkin: duplicate pre-checkin")
    rescue => e
      OpenStruct.new(success?: false, message: "Failed to start pre-checkin: #{e.message}")
    end
  end
end
