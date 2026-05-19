module ChannelManagers
  class IngestRevisionJob < ApplicationJob
    queue_as :default
    retry_on Channex::Client::RetryableRequestError, wait: :exponentially_longer, attempts: 8

    def perform(hotel_id, revision_id)
      hotel = Hotel.find(hotel_id)
      client = Channex::Client.new

      Rails.logger.info("Channel Manager: Ingesting revision #{revision_id} for hotel #{hotel.name}")

      # Pull full revision data
      response = client.get("/booking_revisions/#{revision_id}")
      if response[:error] || response["error"]
        if response[:retryable] || response["retryable"]
          raise Channex::Client::RetryableRequestError, "Ingest revision retryable failure: #{response[:details] || response['details'] || response}"
        end

        Rails.logger.error("Channel Manager Revision Fetch Failed for ID #{revision_id}: #{response}")
        return
      end

      return unless response["data"]

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(hotel)
      booking_data = adapter.ingest_booking(payload: response)

      result = ChannelManagers::IngestBookingService.new(booking_data: booking_data).call

      if result.success?
        Rails.logger.info("Channel Manager: Successfully ingested revision #{revision_id}. Acknowledging...")
        # Channex expects acknowledgement on the processed booking revision itself.
        ack_response = client.post("/booking_revisions/#{revision_id}/ack")
        if ack_response[:error] || ack_response["error"]
          if ack_response[:retryable] || ack_response["retryable"]
            raise Channex::Client::RetryableRequestError, "Ack retryable failure: #{ack_response[:details] || ack_response['details'] || ack_response}"
          end

          Rails.logger.error("Channel Manager Ack Failed for ID #{revision_id}: #{ack_response}")
        else
          Rails.logger.info("Channel Manager: Acknowledged revision #{revision_id}")
        end
      else
        Rails.logger.error "Channel Manager Ingestion Failed for ID #{revision_id}: #{result.message}"
      end
    end
  end
end
