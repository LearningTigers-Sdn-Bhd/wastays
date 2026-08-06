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

      page = 1
      per_page = 100
      ingested_count = 0
      errors = []

      loop do
        response = client.get("/booking_revisions/feed", {
          "order[inserted_at]" => "asc",
          "page" => page,
          "limit" => per_page
        })

        if response[:error] || response["error"]
          return OpenStruct.new(success?: false, message: "Failed to fetch booking revisions: #{response[:details] || response['details'] || response}")
        end

        revisions = Array(response["data"]).select do |revision|
          attributes = revision["attributes"] || revision
          (attributes["property_id"] || revision["property_id"]) == property_id
        end

        revisions.each do |revision|
          begin
            ChannelManagers::IngestRevisionJob.perform_now(@hotel.id, revision["id"])
            ingested_count += 1
          rescue => e
            errors << "Revision #{revision['id']}: #{e.message}"
          end
        end

        # Check for next page
        meta = response["meta"]
        if meta && meta["pagination"]
          current_page = meta.dig("pagination", "current_page")
          total_pages = meta.dig("pagination", "total_pages")
          break if current_page >= total_pages
          page += 1
        else
          break if Array(response["data"]).size < per_page
          page += 1
        end
      end

      if errors.any?
        OpenStruct.new(success?: true, ingested_count: ingested_count, message: "Sync partially successful. Errors: #{errors.join(', ')}")
      else
        OpenStruct.new(success?: true, ingested_count: ingested_count, message: "Successfully synced #{ingested_count} booking revisions.")
      end
    end

    private

    def mapping_for(record)
      ChannelMapping.find_by(provider: "channex", mappable: record)
    end
  end
end
