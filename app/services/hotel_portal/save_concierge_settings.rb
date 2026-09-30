# frozen_string_literal: true

module HotelPortal
  class SaveConciergeSettings
    def self.call(hotel, permitted_params)
      hotel.update(permitted_params.slice(
        :guest_chat_enabled,
        :concierge_refund_requests_enabled,
        :concierge_menu_style
      ))
    end
  end
end
