# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  # One-shot recovery for a poller outage longer than Channex's 30-minute feed
  # window, after which unacked revisions stop being re-served. Lists the
  # bookings Channex created since the outage began and replays each one's
  # latest revision through the normal ingest path, which ignores revisions we
  # already hold. Run it by hand (rake channex:recover_bookings); it is not a
  # schedule, because re-pulling bookings while the poller is healthy is waste.
  class RecoverBookingsService
    PER_PAGE = 100

    def initialize(hotel:, since:)
      @hotel = hotel
      @since = since
    end

    def call
      return failure("Channel manager not selected") unless @hotel.channel_manager_enabled?

      property_id = @hotel.channel_mapping&.external_id
      return failure("Hotel has no Channex property yet") unless ConnectionState.provisioned?(@hotel)

      client = Channex::Client.new
      replayed = 0
      errors = []
      page = 1

      loop do
        response = client.get("/bookings", {
          "filter[property_id]" => property_id,
          "filter[inserted_at][gte]" => @since.utc.iso8601,
          "pagination[page]" => page,
          "pagination[limit]" => PER_PAGE
        })
        if response[:error] || response["error"]
          return failure("Failed to list bookings: #{response[:details] || response['details'] || response}")
        end

        bookings = Array(response["data"])
        bookings.each do |booking|
          revision_id = revision_id_for(booking, property_id)
          next if revision_id.blank?

          begin
            ChannelManagers::IngestRevisionJob.perform_now(@hotel.id, revision_id)
            replayed += 1
          rescue => e
            errors << "Revision #{revision_id}: #{e.message}"
          end
        end

        break if bookings.size < PER_PAGE

        page += 1
      end

      message = "Replayed #{replayed} booking(s) created since #{@since.utc.iso8601}."
      message += " #{errors.size} failed: #{errors.join('; ')}" if errors.any?
      OpenStruct.new(success?: errors.empty?, replayed_count: replayed, errors: errors, message: message)
    end

    private

    # The filter params are not in Channex's public docs, so do not trust them
    # to have scoped the list: drop anything for another property.
    def revision_id_for(booking, property_id)
      attributes = booking["attributes"] || booking
      return if attributes["property_id"].present? && attributes["property_id"] != property_id

      attributes["revision_id"]
    end

    def failure(message)
      OpenStruct.new(success?: false, replayed_count: 0, errors: [], message: message)
    end
  end
end
