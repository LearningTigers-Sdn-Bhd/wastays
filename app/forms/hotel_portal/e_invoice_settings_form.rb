# frozen_string_literal: true

module HotelPortal
  class EInvoiceSettingsForm
    include ActiveModel::Model

    attr_reader :hotel, :params

    def initialize(hotel, params)
      @hotel = hotel
      @params = params
    end

    def setting
      @setting ||= hotel.e_invoice_setting || hotel.build_e_invoice_setting
    end

    def save
      setting.update(setting_params)
    end

    def errors
      setting.errors
    end

    private

    def setting_params
      params.require(:e_invoice_setting).permit(
        :enabled,
        :intermediary_enabled,
        :hotel_tin,
        :hotel_brn,
        :supplier_msic_code,
        :supplier_business_description,
        :supplier_sst_registration_number,
        :supplier_address_line1,
        :supplier_address_line2,
        :supplier_city,
        :supplier_postal_code,
        :supplier_state_code,
        :supplier_country_code,
        :supplier_contact_phone,
        :supplier_contact_email
      )
    end
  end
end
