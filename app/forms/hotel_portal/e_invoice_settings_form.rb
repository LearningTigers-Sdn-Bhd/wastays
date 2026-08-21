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
      attributes = setting_params
      # A blank secret means "leave it alone", so an admin editing the address
      # does not silently wipe the hotel's LHDN access.
      attributes = attributes.except(:client_secret) if attributes[:client_secret].blank?
      attributes = attributes.except(:signing_private_key) if attributes[:signing_private_key].blank?

      # Switching to production means every submission from here on files a
      # real e-invoice with LHDN, not a sandbox one - not something a single
      # unremarkable form save should be able to do by accident. The
      # checkbox is rendered by Stimulus (see e_invoice_settings_controller.js)
      # only when the environment select is on "production", but that is a
      # UX nicety, not the enforcement: this check is what actually stops a
      # crafted request from skipping it.
      if going_to_production_without_confirmation?(attributes)
        setting.errors.add(:api_environment, "can't be switched to production without confirming - check the box that appears when you select it")
        return false
      end

      setting.update(attributes)
    end

    def errors
      setting.errors
    end

    private

    def going_to_production_without_confirmation?(attributes)
      attributes[:api_environment] == "production" &&
        !ActiveModel::Type::Boolean.new.cast(params.dig(:e_invoice_setting, :confirm_production))
    end

    def setting_params
      params.require(:e_invoice_setting).permit(
        # intermediary_enabled is deliberately not permitted: WAStays is not a
        # registered LHDN intermediary, so the hotel admin does not offer it and
        # a crafted request must not switch it on either.
        #
        # supplier_country_code is deliberately not permitted either: every
        # hotel on this platform is a Malaysian entity, so this is computed
        # (EInvoiceSetting#supplier_country_code_value) rather than typed,
        # which is one less place for a typo to reach a real LHDN submission.
        :enabled,
        :api_environment,
        :client_id,
        :client_secret,
        :signature_enabled,
        :signing_certificate,
        :signing_private_key,
        :supplier_msic_code,
        :supplier_business_description,
        :supplier_address_line1,
        :supplier_address_line2,
        :supplier_city,
        :supplier_postal_code,
        :supplier_state_code,
        :supplier_contact_phone,
        :supplier_contact_email
      )
    end
  end
end
