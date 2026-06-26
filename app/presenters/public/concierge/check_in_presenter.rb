# frozen_string_literal: true

module Public
  module Concierge
    class CheckInPresenter
      attr_reader :booking, :hotel

      def initialize(booking:, hotel:)
        @booking = booking
        @hotel = hotel
      end

      def subtitle
        if pre_checkin_completed?
          "Your pre-check-in is complete. Confirm below to check in and get your room assigned."
        else
          "Complete your guest registration below to check in and get your room assigned."
        end
      end

      def registration_required?
        !pre_checkin_completed?
      end

      def pre_checkin_completed?
        booking.pre_checkin&.completed?
      end

      def document_types
        [
          [ "MyKad (IC)", "ic" ],
          [ "Passport", "passport" ]
        ]
      end

      def default_country
        booking.guest_country.presence || "Malaysia"
      end

      def error_message_for(error_code)
        case error_code
        when :wrong_date
          "Your check-in date is #{booking.check_in.strftime('%d %b %Y')}. You can check in on that day#{hotel.property_policy&.check_in_time.present? ? ' from ' + hotel.property_policy.check_in_time : ''}."
        when :too_early
          "Check-in opens at #{hotel.property_policy.check_in_time}. Please come back later or see the front desk."
        when :no_room_available
          "No rooms are ready right now. Please proceed to the front desk and our staff will check you in shortly."
        when :registration_error
          "Please check the details below and try again."
        when :too_far_away
          "You are too far from the hotel to self-check-in. Self-check-in is only available when you are physically at the property."
        when :missing_location
          "Location access is required for verification. Please enable GPS and allow location permissions."
        else
          nil
        end
      end
    end
  end
end
