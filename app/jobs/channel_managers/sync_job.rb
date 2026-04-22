module ChannelManagers
  class SyncJob < ApplicationJob
    queue_as :default

    def perform(hotel_id, start_date, end_date)
      hotel = Hotel.find(hotel_id)
      return if hotel.preferred_channel_manager.blank?

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(hotel)
      adapter.push_ari(date_range: (start_date.to_date..end_date.to_date))
    end
  end
end
