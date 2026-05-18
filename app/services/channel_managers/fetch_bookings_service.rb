# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  class FetchBookingsService
    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      return OpenStruct.new(success?: false, message: "Channel manager not selected") if @hotel.preferred_channel_manager.blank?

      client = Channex::Client.new
      property_id = mapping_for(@hotel).external_id

      # Fetch future bookings for this property
      # We filter by property_id and only include active/confirmed ones if desired,
      # but usually we want to sync all upcoming.
      response = client.get("/bookings", { "filter[property_id]" => property_id })

      if response[:error] || response["error"]
        return OpenStruct.new(success?: false, message: "Failed to fetch bookings: #{response[:details] || response['details'] || response}")
      end

      bookings = response["data"] || []
      ingested_count = 0
      errors = []

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(@hotel)

      bookings.each do |booking_payload|
        begin
          # The list endpoint might have slightly different structure than the revision endpoint,
          # but ChannexAdapter#ingest_booking is designed to be robust.
          booking_data = adapter.ingest_booking(payload: booking_payload)
          result = ChannelManagers::IngestBookingService.new(booking_data: booking_data).call

          if result.success?
            ingested_count += 1
          else
            errors << "Booking #{booking_payload['id']}: #{result.message}"
          end
        rescue => e
          errors << "Booking #{booking_payload['id']}: #{e.message}"
        end
      end

      if errors.any?
        OpenStruct.new(success?: true, ingested_count: ingested_count, message: "Sync partially successful. Errors: #{errors.join(', ')}")
      else
        OpenStruct.new(success?: true, ingested_count: ingested_count, message: "Successfully synced #{ingested_count} bookings.")
      end
    end

    private

    def mapping_for(record)
      ChannelMapping.find_by(provider: "channex", mappable: record)
    end
  end
end
