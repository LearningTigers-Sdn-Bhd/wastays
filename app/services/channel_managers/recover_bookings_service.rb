# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  # One-shot recovery for a poller outage longer than Channex's 30-minute feed
  # window, after which unacked revisions stop being re-served. Lists every
  # booking revision Channex received since the outage began (new, modified
  # and cancelled alike, so a change to an older booking is not missed) and
  # replays them oldest first through the normal ingest path, which ignores
  # revisions we already hold. Run it by hand (rake channex:recover_bookings);
  # it is not a schedule, because re-pulling while the poller is healthy is
  # waste.
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
        response = client.get("/booking_revisions", {
          "filter[property_id]" => property_id,
          "filter[inserted_at][gte]" => @since.utc.iso8601,
          "order[inserted_at]" => "asc",
          "pagination[page]" => page,
          "pagination[limit]" => PER_PAGE
        })
        if response[:error] || response["error"]
          return failure("Failed to list booking revisions: #{response[:details] || response['details'] || response}")
        end

        revisions = Array(response["data"])
        revisions.each do |revision|
          next unless for_property?(revision, property_id)

          revision_id = revision["id"]
          begin
            outcome = ChannelManagers::IngestRevisionJob.perform_now(@hotel.id, revision_id)
            if outcome == :acked
              replayed += 1
            else
              errors << "Revision #{revision_id}: not acknowledged (see error tracker; a retry may be queued)"
            end
          rescue => e
            errors << "Revision #{revision_id}: #{e.message}"
          end
        end

        total = response.dig("meta", "total").to_i
        break if revisions.empty? || page * PER_PAGE >= total

        page += 1
      end

      message = "Replayed #{replayed} booking revision(s) received since #{@since.utc.iso8601}."
      message += " #{errors.size} failed: #{errors.join('; ')}" if errors.any?
      OpenStruct.new(success?: errors.empty?, replayed_count: replayed, errors: errors, message: message)
    end

    private

    # The list filters are not in Channex's public docs (they worked on staging
    # on 2026-10-12), so do not trust them alone: drop anything for another
    # property.
    def for_property?(revision, property_id)
      attributes = revision["attributes"] || {}
      attributes["property_id"].blank? || attributes["property_id"] == property_id
    end

    def failure(message)
      OpenStruct.new(success?: false, replayed_count: 0, errors: [], message: message)
    end
  end
end
