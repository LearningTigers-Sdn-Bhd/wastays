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
      SaveGeneralSettings.call(
        hotel,
        hotel_params,
        property_policy_params,
        should_update_property_policy?
      )
    end

    private

    def hotel_params
      permitted = params.require(:hotel).permit(
        :default_currency, :time_zone, :geolocation_enabled, :auto_assign_rooms_enabled,
        :business_starts_at, :business_ends_at, :arrival_grace_period_hours,
        :agent_payment_hold_amount, :agent_payment_hold_unit,
        :guest_registration_card_terms,
        guest_registration_card_fields: [],
        hotel_boat_setting_attributes: [ :id, :breakfast_time, :lunch_time, :dinner_time ],
        property_policy_attributes: [ :id, :check_in_time, :check_out_time ]
      )

      if permitted.key?(:guest_registration_card_fields)
        permitted[:guest_registration_card_fields] = permitted[:guest_registration_card_fields].reject(&:blank?) & GuestRegistrationCard::DISPLAY_FIELDS.keys
      end

      permitted
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
  end
end
