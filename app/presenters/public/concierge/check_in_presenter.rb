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
        when :closed_check_in_date
          "We're unable to complete self check-in for this stay. Please visit the front desk for assistance."
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

      def geolocation_active?
        hotel.geolocation_enabled? && !registration_required?
      end

      def form_data(view_context, is_mobile: false)
        controllers = [ "scanner", "pre-checkin-document" ]
        controllers << "guest-dob" if registration_required?
        controllers << "geolocation-check-in" if geolocation_active?

        data = {
          controller: controllers.join(" "),
          pre_checkin_document_is_concierge_value: true
        }

        if geolocation_active?
          data.merge!(
            geolocation_check_in_hotel_latitude_value: hotel.latitude,
            geolocation_check_in_hotel_longitude_value: hotel.longitude,
            geolocation_check_in_allowed_radius_value: 50,
            geolocation_check_in_refresh_icon_value: view_context.cached_icon("refresh-cw", class: "w-4 h-4 mr-1.5 inline-block align-middle animate-spin-slow"),
            geolocation_check_in_is_mobile_value: is_mobile
          )
        end

        data
      end

      HIDDEN_CLASSES = "hidden opacity-0 scale-95 -translate-y-2"

      def guest_document_type
        booking.guest_document_type
      end

      def upload_section_class
        guest_document_type.blank? ? HIDDEN_CLASSES : ""
      end

      def front_container_class
        if guest_document_type.blank?
          HIDDEN_CLASSES
        elsif guest_document_type == "passport"
          "md:col-span-2 w-full"
        else
          ""
        end
      end

      def back_container_class
        guest_document_type == "ic" ? "" : HIDDEN_CLASSES
      end

      def front_scanner_label
        guest_document_type == "passport" ? "Passport Photo Page" : "Front ID Card"
      end

      def front_scanner_height_class
        guest_document_type == "passport" ? "h-44 md:h-64 md:max-w-[700px]" : "h-44"
      end
    end
  end
end
