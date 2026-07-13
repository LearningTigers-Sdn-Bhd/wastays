# frozen_string_literal: true

module ChannelManagers
  class SyncAvailabilityRuleJob < ApplicationJob
    queue_as :default

    def perform(rule_id, action = "sync", options = {})
      if action == "delete"
        hotel_id = options[:hotel_id] || options["hotel_id"]
        external_id = options[:external_id] || options["external_id"]
        hotel = Hotel.find_by(id: hotel_id)
        return if hotel.nil? || hotel.preferred_channel_manager.blank?

        adapter = ChannelManagers::SyncOrchestrator.adapter_for(hotel)
        adapter.delete_channel_availability_rule(external_id)
        return
      end

      rule = ChannelAvailabilityRule.find_by(id: rule_id)
      return if rule.nil?

      hotel = rule.hotel
      return if hotel.preferred_channel_manager.blank?

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(hotel)

      if action == "sync"
        if rule.external_id.present?
          adapter.update_channel_availability_rule(rule)
        else
          adapter.create_channel_availability_rule(rule)
        end
      end
    end
  end
end
