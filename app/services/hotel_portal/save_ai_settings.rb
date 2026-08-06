# frozen_string_literal: true

module HotelPortal
  class SaveAiSettings
    def self.call(hotel, permitted_params)
      attrs = permitted_params.slice(:ai_provider_enabled, :ai_concierge_tone, :ai_provider_name, :ai_provider_key)
      enabled = ActiveModel::Type::Boolean.new.cast(attrs[:ai_provider_enabled])

      hotel.assign_attributes(attrs)
      hotel.errors.add(:ai_provider_name, "can't be blank") if enabled && hotel.ai_provider_name.blank?
      hotel.errors.add(:ai_provider_key, "can't be blank") if enabled && hotel.ai_provider_key.blank?
      raise ActiveRecord::RecordInvalid, hotel if hotel.errors.any?

      hotel.save!(validate: false)
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
