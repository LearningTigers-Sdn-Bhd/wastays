# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  class FullRefreshService
    # wait delays the push, so a batch of hotels can be spread out.
    def initialize(hotel:, wait: nil)
      @hotel = hotel
      @wait = wait
    end

    def call
      return OpenStruct.new(success?: false, message: "Channel publishing is unavailable while this property is in training.") if @hotel.training_mode?
      return OpenStruct.new(success?: false, message: "Channel manager not selected") unless @hotel.channel_manager_enabled?

      # A full refresh is the moment to pick up newly connected OTAs; routine
      # pushes reuse the cached channel list.
      Rails.cache.delete("channex:channels:#{@hotel.id}")

      # We use 500 days as per Channex Certification requirements. The window
      # opens on the hotel's today: the 2 am refresh in Kuala Lumpur runs while
      # it is still yesterday in UTC.
      start_date = @hotel.hotel_time_zone.today
      end_date = start_date + 499.days

      ChannelManagers::SyncJob.set(wait: @wait).perform_later(
        @hotel.id,
        start_date,
        end_date,
        sync_availability: true,
        sync_rates: true,
        sync_restrictions: true,
        room_type_ids: nil,
        rate_plan_ids: nil
      )

      OpenStruct.new(success?: true, message: "Full refresh queued for 500 days of data.")
    end
  end
end
