# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  class FullRefreshService
    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      return OpenStruct.new(success?: false, message: "Channel publishing is unavailable while this property is in training.") if @hotel.training_mode?
      return OpenStruct.new(success?: false, message: "Channel manager not selected") if @hotel.preferred_channel_manager.blank?

      # We use 500 days as per Channex Certification requirements
      start_date = Date.current
      end_date = start_date + 499.days

      ChannelManagers::SyncJob.perform_later(
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
