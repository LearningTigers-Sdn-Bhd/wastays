# frozen_string_literal: true

module HotelPortal
  class EInvoiceSettingsController < HotelPortal::BaseController
    before_action :set_hotel
    before_action :authorize!

    def show
      @e_invoice_setting = current_hotel.e_invoice_setting || current_hotel.build_e_invoice_setting
    end

    def update
      @e_invoice_setting = current_hotel.e_invoice_setting || current_hotel.build_e_invoice_setting(hotel: current_hotel)

      if @e_invoice_setting.update(e_invoice_setting_params)
        redirect_to hotel_settings_path(current_hotel, tab: "einvoice"), notice: "E-Invoice settings saved."
      else
        redirect_to hotel_settings_path(current_hotel, tab: "einvoice"),
          alert: @e_invoice_setting.errors.full_messages.to_sentence
      end
    end

    private

    def set_hotel
      @hotel = current_hotel
    end

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def e_invoice_setting_params
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
