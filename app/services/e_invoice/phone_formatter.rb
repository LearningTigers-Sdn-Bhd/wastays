# frozen_string_literal: true

module EInvoice
  module PhoneFormatter
    DEFAULT_PHONE = "+60123456789"

    private

    def format_phone(phone)
      return DEFAULT_PHONE if phone.blank?

      phone.to_s.strip.then { |value| value.start_with?("+") ? value : "+#{value.gsub(/\D/, "")}" }
    end
  end
end
