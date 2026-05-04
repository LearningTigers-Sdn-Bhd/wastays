module AiConciergeV3
  module Tools
    class GenerateBookingUrlTool
      def initialize(hotel:, selected_option:, guest_phone: nil, guest_name: nil, guest_email: nil)
        @hotel = hotel
        @selected_option = selected_option
        @guest_phone = guest_phone
        @guest_name = guest_name
        @guest_email = guest_email
      end

      def call
        result = BookingEngine::CreateQuote.new(
          hotel_id: hotel.id,
          room_type_id: selected_option.fetch("room_type_id"),
          check_in: selected_option.fetch("check_in"),
          check_out: selected_option.fetch("check_out"),
          adults: selected_option["adults"],
          children: selected_option["children"],
          room_count: selected_option["room_count"],
          guest_phone: guest_phone,
          guest_name: guest_name,
          guest_email: guest_email
        ).call

        return { "success" => false, "error" => result.message } unless result.success?

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

      attr_reader :hotel, :selected_option, :guest_phone, :guest_name, :guest_email

      def default_host
        host_options = Rails.application.config.action_mailer.default_url_options || {}
        protocol = host_options[:protocol].presence || "http"
        host = host_options[:host].presence || "example.com"
        port = host_options[:port].presence
        ["#{protocol}://#{host}", port].compact.join(port ? ":" : "")
      end
    end
  end
end
