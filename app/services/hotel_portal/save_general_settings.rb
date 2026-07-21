# frozen_string_literal: true

module HotelPortal
  class SaveGeneralSettings
    def self.call(hotel, permitted_params, property_policy_params, should_update_policy)
      ActiveRecord::Base.transaction do
        hotel.update!(permitted_params)

        if should_update_policy
          policy = fresh_property_policy(hotel)
          policy.update!(property_policy_params)
        end
      end

      if (hotel.saved_changes.keys & %w[name city country default_currency amenities]).any?
        if hotel.preferred_channel_manager.present? && hotel.channel_mapping.present?
          ChannelManagers::SyncStructureJob.perform_later("Hotel", hotel.id, "sync")
        end
      end

      true
    rescue ActiveRecord::RecordInvalid, FrozenError
      false
    end

    private

    def self.fresh_property_policy(hotel)
      policy = hotel.property_policy
      return hotel.build_property_policy if policy.blank?

      policy.frozen? ? PropertyPolicy.find(policy.id) : policy
    end
  end
end
