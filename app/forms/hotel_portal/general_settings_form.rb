# frozen_string_literal: true

module HotelPortal
  class GeneralSettingsForm
    include ActiveModel::Model

    attr_reader :hotel, :params

    def initialize(hotel, params)
      @hotel = hotel
      @params = params
    end

    def save
      return update_ai_configuration! if ai_configuration_form?

      ActiveRecord::Base.transaction do
        hotel.update!(hotel_params)

        if should_update_property_policy?
          policy = fresh_property_policy
          policy.update!(property_policy_params)
        end
      end
      true
    rescue ActiveRecord::RecordInvalid, FrozenError
      false
    end

    private

    def ai_configuration_form?
      params[:form_id].to_s == "ai_configuration"
    end

    def update_ai_configuration!
      attrs = hotel_params.slice(:ai_provider_enabled, :ai_concierge_tone, :ai_provider_name, :ai_provider_key)
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

    def hotel_params
      params.require(:hotel).permit(
        :default_currency, :time_zone,
        :ai_provider_enabled, :ai_concierge_tone, :ai_provider_name, :ai_provider_key,
        :business_starts_at, :business_ends_at, :arrival_grace_period_hours,
        property_policy_attributes: [ :id, :check_in_time, :check_out_time ]
      )
    end

    def property_policy_params
      params.require(:hotel).permit(
        property_policy_attributes: [ :check_in_time, :check_out_time ]
      ).fetch(:property_policy_attributes, {})
    end

    def should_update_property_policy?
      return false unless params[:form_id].to_s == "hotel_settings"

      attrs = params.dig(:hotel, :property_policy_attributes)
      attrs.present? && (attrs[:check_in_time].present? || attrs[:check_out_time].present?)
    end

    def fresh_property_policy
      policy = hotel.property_policy
      return hotel.build_property_policy if policy.blank?

      policy.frozen? ? PropertyPolicy.find(policy.id) : policy
    end
  end
end
