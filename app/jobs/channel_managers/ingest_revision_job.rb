module ChannelManagers
  class IngestRevisionJob < ApplicationJob
    queue_as :default

    def perform(hotel_id, revision_id)
      hotel = Hotel.find(hotel_id)
      client = Channex::Client.new

      # Pull full revision data
      response = client.get("/booking_revisions/#{revision_id}")
      return unless response["data"]

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(hotel)
      booking_data = adapter.ingest_booking(payload: response)

      result = ChannelManagers::IngestBookingService.new(booking_data: booking_data).call

      if result.success?
        # Acknowledge the booking (Mandatory)
        client.post("/bookings/#{booking_data[:channel_manager_reference]}/ack")
      else
        Rails.logger.error "Channex Ingestion Failed: #{result.message}"
      end
    end
  end
end
