# frozen_string_literal: true

module ChannelManagers
  class ConnectionState
    def self.provisioned?(hotel)
      provider = hotel.preferred_channel_manager
      mapping = hotel.channel_mapping

      SyncOrchestrator::ADAPTERS.key?(provider) &&
        mapping.present? &&
        mapping.external_id.present? &&
        !mapping.external_id.start_with?("pending")
    end
  end
end
