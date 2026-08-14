module ChannelManagers
  class SyncJob < ApplicationJob
    queue_as :default
    retry_on Channex::Client::RetryableRequestError, wait: :exponentially_longer, attempts: 8

    def perform(hotel_id, start_date, end_date, sync_availability: true, sync_rates: true, sync_restrictions: true, room_type_ids: nil, rate_plan_ids: nil, rate_plan_fields: nil)
      hotel = Hotel.find(hotel_id)
      return if hotel.training_mode?
      return if hotel.preferred_channel_manager.blank?

      # Clear cached connected channels to ensure fresh sync data
      Rails.cache.delete("channex:channels:#{hotel.id}")

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(hotel)
      result = adapter.push_ari(
        date_range: (start_date.to_date..end_date.to_date),
        sync_availability: sync_availability,
        sync_rates: sync_rates,
        sync_restrictions: sync_restrictions,
        room_type_ids: room_type_ids,
        rate_plan_ids: rate_plan_ids,
        rate_plan_fields: rate_plan_fields
      )

      # Transport failures, 429s and 5xx responses are raised by the adapter
      # and handled by retry_on above. Unsupported pricing and Channex
      # validation warnings are terminal until an operator changes the input.
      return if result.success? || result.unsupported?

      Rails.logger.error(
        "Channel manager sync failed without retry hotel_id=#{hotel.id} " \
        "status=#{result.status} message=#{result.message.inspect} warnings=#{result.warnings.to_json}"
      )
    end
  end
end
