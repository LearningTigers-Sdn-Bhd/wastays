# frozen_string_literal: true

module ChannelManagers
  # ARI pushes are driven by edits, so a push that failed for good, or an edit
  # that never fired its callback, leaves the OTAs wrong until someone hits
  # "full refresh". This re-pushes every connected hotel once a night.
  class NightlyFullRefreshJob < ApplicationJob
    queue_as :default

    def perform
      queued = 0

      Hotel.where(preferred_channel_manager: SyncOrchestrator::ADAPTERS.keys).includes(:channel_mapping).find_each do |hotel|
        next unless ConnectionState.provisioned?(hotel)

        result = FullRefreshService.new(hotel: hotel).call
        if result.success?
          queued += 1
        else
          Rails.logger.warn("Channex nightly refresh skipped hotel_id=#{hotel.id}: #{result.message}")
        end
      end

      Rails.logger.info("Channex nightly refresh queued #{queued} hotel(s)")
    end
  end
end
