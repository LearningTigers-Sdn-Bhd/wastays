require 'ostruct'

module GuestArrival
  class SyncWorkflowEvent
    def initialize(booking, event_payload)
      @booking = booking
      @event_type = event_payload[:event_type]
      @data = event_payload[:data] || {}
      @pre_checkin = @booking.pre_checkin
    end

    def call
      return OpenStruct.new(success?: false, message: "Pre-checkin record not found") unless @pre_checkin

      ActiveRecord::Base.transaction do
        case @event_type
        when 'flow_started'
          update_status('in_progress')
        when 'document_uploaded'
          @pre_checkin.update!(document_status: 'uploaded')
        when 'signature_completed'
          @pre_checkin.update!(signature_status: 'signed')
        when 'flow_completed'
          finalize_pre_checkin
        when 'flow_failed'
          update_status('failed')
        end

        OpenStruct.new(success?: true)
      end
    rescue => e
      OpenStruct.new(success?: false, message: "Sync failed: #{e.message}")
    end

    private

    def update_status(status)
      @pre_checkin.update!(status: status)
      @booking.update!(pre_checkin_status: status)
    end

    def finalize_pre_checkin
      @pre_checkin.update!(
        status: 'completed',
        completed_at: Time.current,
        metadata: @pre_checkin.metadata.to_h.merge(final_payload: @data)
      )
      @booking.update!(
        pre_checkin_status: 'completed',
        guarantee_method: 'pre_checkin_completed' # Default if flow completed
      )
    end
  end
end
