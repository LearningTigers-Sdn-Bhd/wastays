module Public
  module Concierge
    class ContactController < BaseController
      def show
        @policy = @hotel.property_policy
        @whatsapp_link = whatsapp_link
        @maps_link = maps_link
        render "show_mobile" if mobile_request?
      end

      private

      def whatsapp_link
        number = @hotel.whatsapp_number.presence || @hotel.contact_phone.presence
        return nil unless number
        digits = number.gsub(/\D/, "")
        "https://wa.me/#{digits}"
      end

      def maps_link
        query = [ @hotel.address, @hotel.city, @hotel.country ].compact_blank.join(", ")
        return nil if query.blank?
        "https://www.google.com/maps/search/?api=1&query=#{CGI.escape(query)}"
      end
    end
  end
end
