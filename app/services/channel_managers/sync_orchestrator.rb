# frozen_string_literal: true

module ChannelManagers
  class SyncOrchestrator
    ADAPTERS = {
      "channex" => ChannelManagers::ChannexAdapter
    }.freeze

    def self.adapter_for(hotel)
      provider = hotel.preferred_channel_manager
      adapter_class = ADAPTERS[provider]

      raise "Unsupported channel manager: #{provider}" unless adapter_class

      adapter_class.new(hotel: hotel)
    end
  end
end
