# frozen_string_literal: true

module AiConcierge
  module MessageBuilders
    class ExistingBookingBuilder < BaseBuilder
      def call(reply_type)
        case reply_type.to_sym
        when :ask_existing_booking_confirmation_code
          "Enter your booking confirmation code. You can find it in your booking email."
        when :existing_booking_portal
          "You can manage this through the Guest Portal. I can send a secure login link to the email saved on your booking."
        when :existing_booking_cancellation_portal
          "You can submit an eligible cancellation and refund request through the Guest Portal. " \
            "I can send a secure login link to the email saved on your booking."
        when :existing_booking_not_found
          "I could not send a login link with that confirmation code. Check the code and try again."
        when :magic_link_sent
          "Your secure login link is on its way to #{context[:masked_email]}. Open it to manage your booking. " \
            "I am here if you need more help."
        when :magic_link_cooldown
          "A login link was already sent to #{context[:masked_email]}. Please wait two minutes before you request another link."
        when :magic_link_unavailable
          magic_link_unavailable_message
        when :booking_support_requested
          "I have asked the hotel team to help with your booking. They will reply here when available. " \
            "You can continue chatting while you wait."
        when :booking_cancellation_support_requested
          "I have asked the hotel team to help with your cancellation request. They will reply when available."
        when :unsupported_date_change
          "Booking-date changes are not available in the Guest Portal yet. For now, I can ask the hotel team to help you " \
            "change your check-in date. Would you like me to contact them, or would you like help with something else?"
        when :unsupported_room_change
          unsupported_feature_message("room changes")
        when :unsupported_guest_change
          unsupported_feature_message("guest-detail changes")
        when :unsupported_payment_change
          unsupported_feature_message("payment changes")
        when :unsupported_exception
          "This request needs a review from the hotel team. I can ask them to help you here. " \
            "Would you like me to contact them, or would you like help with something else?"
        end
      end

      private

      def magic_link_unavailable_message
        "I cannot send a login link for this booking, but the hotel team can help you here. " \
          "Would you like me to ask them to review your request?"
      end

      def unsupported_feature_message(feature)
        "#{feature.capitalize} are not available in the Guest Portal yet. For now, I can ask the hotel team to help you. " \
          "Would you like me to contact them, or would you like help with something else?"
      end
    end
  end
end
