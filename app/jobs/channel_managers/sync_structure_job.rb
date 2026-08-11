# frozen_string_literal: true

module ChannelManagers
  class SyncStructureJob < ApplicationJob
    queue_as :default
    retry_on Channex::Client::RetryableRequestError, wait: :exponentially_longer, attempts: 8

    def perform(mappable_type, mappable_id, action = "sync", options = {})
      if action == "delete"
        hotel_id = options[:hotel_id] || options["hotel_id"]
        external_id = options[:external_id] || options["external_id"]
        hotel = Hotel.find_by(id: hotel_id)
        return if hotel.nil? || hotel.preferred_channel_manager.blank?

        adapter = ChannelManagers::SyncOrchestrator.adapter_for(hotel)
        case mappable_type
        when "RoomType" then adapter.delete_room_type(external_id)
        when "RatePlan" then adapter.delete_rate_plan(external_id)
        when "RoomTypeRatePlan" then adapter.delete_rate_plan(external_id)
        end
        return
      end

      mappable = mappable_type.constantize.find_by(id: mappable_id)
      return if mappable.nil?

      hotel = case mappable_type
      when "RoomType" then mappable.hotel
      when "RatePlan" then mappable.hotel
      when "RoomTypeRatePlan" then mappable.room_type.hotel
      when "Hotel" then mappable
      end

      return if hotel.nil? || hotel.preferred_channel_manager.blank?

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(hotel)

      case action
      when "sync"
        case mappable_type
        when "Hotel" then adapter.sync_hotel
        when "RoomType" then adapter.sync_room_type(mappable)
        when "RoomTypeRatePlan" then adapter.sync_rate_plan(mappable.rate_plan, room_type: mappable.room_type)
        when "RatePlan"
          mappable.room_type_rate_plans.each do |rtrp|
            adapter.sync_rate_plan(rtrp.rate_plan, room_type: rtrp.room_type)
          end
        end
      end
    end
  end
end
