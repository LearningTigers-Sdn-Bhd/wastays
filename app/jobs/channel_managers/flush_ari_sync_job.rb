# frozen_string_literal: true

module ChannelManagers
  class FlushAriSyncJob < ApplicationJob
    queue_as :default

    # The flush only hands its changes to SyncJob, so what can fail here is
    # that hand-off. Retrying re-claims the outbox the failure put back;
    # without it those changes would sit unsent until they expired.
    retry_on ActiveJob::EnqueueError, ActiveRecord::ActiveRecordError, wait: :polynomially_longer, attempts: 5

    def perform(hotel_id)
      hotel = Hotel.find_by(id: hotel_id)
      return if hotel.nil? || !hotel.channel_manager_enabled?

      outbox = AriWindow.new(hotel_id)
      window = outbox.claim
      return if window.blank?

      begin
        start_date = Date.parse(window["min_date"])
        end_date = Date.parse(window["max_date"])
      rescue Date::Error
        return
      end

      begin
        enqueued = ChannelManagers::SyncJob.perform_later(
          hotel_id,
          start_date,
          end_date,
          sync_availability: window.fetch("sync_availability", true),
          sync_rates: window.fetch("sync_rates", true),
          sync_restrictions: window.fetch("sync_restrictions", true),
          room_type_ids: window["room_type_windows"],
          rate_plan_ids: window["rate_plan_windows"],
          rate_plan_fields: window["rate_plan_fields"]
        )
        raise ActiveJob::EnqueueError, "SyncJob was not enqueued for hotel #{hotel_id}" unless enqueued
      rescue StandardError
        outbox.restore(window)
        raise
      end
    end
  end
end
