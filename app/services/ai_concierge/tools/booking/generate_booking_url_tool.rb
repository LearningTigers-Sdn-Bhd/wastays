module AiConcierge
  module Tools
    module Booking
      class GenerateBookingUrlTool
        def initialize(hotel:, selected_option:, guest_phone: nil, guest_name: nil, guest_email: nil, rate_plan_id: nil)
          @hotel = hotel
          @selected_option = selected_option
          @guest_phone = guest_phone
          @guest_name = guest_name
          @guest_email = guest_email
          @rate_plan_id = rate_plan_id
        end

        def call
          validation_error = validate_selected_option
          return validation_error if validation_error

          result = BookingEngine::CreateQuote.new(
            hotel_id: hotel.to_param,
            room_type_id: selected_option.fetch("room_type_id"),
            check_in: selected_option.fetch("check_in"),
            check_out: selected_option.fetch("check_out"),
            adults: selected_option["adults"],
            children: selected_option["children"],
            room_count: selected_option["room_count"],
            guest_phone: guest_phone,
            guest_name: guest_name,
            guest_email: guest_email,
            rate_plan_id: rate_plan_id
          ).call

          return failure("quote_creation_failed", result.message.presence || "Unable to generate quote right now.") unless result.success?
          return failure("quote_missing", "Unable to generate quote right now.") unless result.quote

          {
            "success" => true,
            "booking_url" => Rails.application.routes.url_helpers.quote_url(result.quote.token, host: default_host),
            "total_amount" => result.quote.total_amount.to_f,
            "currency" => result.quote.currency,
            "expires_at" => result.quote.expires_at.iso8601,
            "quote_token" => result.quote.token
          }
        end

        private

        attr_reader :hotel, :selected_option, :guest_phone, :guest_name, :guest_email, :rate_plan_id

        def validate_selected_option
          return failure("invalid_selection", "Unable to generate quote right now.") unless selected_option.is_a?(Hash)

          %w[room_type_id check_in check_out].each do |key|
            return failure("missing_#{key}", "Unable to generate quote right now.") if selected_option[key].blank?
          end

          Date.iso8601(selected_option["check_in"].to_s)
          Date.iso8601(selected_option["check_out"].to_s)
          nil
        rescue Date::Error
          failure("invalid_dates", "Unable to generate quote right now.")
        end

        def failure(error_code, message)
          {
            "success" => false,
            "error" => message,
            "error_code" => error_code
          }
        end

        def default_host
          host_options = Rails.application.config.action_mailer.default_url_options || {}
          protocol = host_options[:protocol].presence || "http"
          host = host_options[:host].presence || "example.com"
          port = host_options[:port].presence
          [ "#{protocol}://#{host}", port ].compact.join(port ? ":" : "")
        end
      end
    end
  end
end
