module ChannelManagers
  class IngestRevisionJob < ApplicationJob
    queue_as :default
    retry_on Channex::Client::RetryableRequestError, wait: :exponentially_longer, attempts: 8

    def perform(hotel_id, revision_id)
      hotel = Hotel.find(hotel_id)
      client = Channex::Client.new

      # Pull full revision data
      response = client.get("/booking_revisions/#{revision_id}")
      if response[:error] || response["error"]
        if response[:retryable] || response["retryable"]
          raise Channex::Client::RetryableRequestError, "Ingest revision retryable failure: #{response[:details] || response['details'] || response}"
        end

        Rails.logger.error("Channel Manager Revision Fetch Failed: #{response}")
        return
      end

      return unless response["data"]

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(hotel)
      booking_data = adapter.ingest_booking(payload: response)

      result = ChannelManagers::IngestBookingService.new(booking_data: booking_data).call

      if result.success?
        # Acknowledge the booking (Mandatory)
        ack_response = client.post("/bookings/#{booking_data[:channel_manager_reference]}/ack")
        if ack_response[:error] || ack_response["error"]
          if ack_response[:retryable] || ack_response["retryable"]
            raise Channex::Client::RetryableRequestError, "Ack retryable failure: #{ack_response[:details] || ack_response['details'] || ack_response}"
          end

          Rails.logger.error("Channel Manager Ack Failed: #{ack_response}")
        end
      else
        Rails.logger.error "Channel Manager Ingestion Failed: #{result.message}"
      end
    end
  end
end
