require "net/http"
require "json"
require "openssl"
require "base64"

module Payments
  module GatewayAdapters
    class Razorpay < Payments::BaseAdapter
      API_BASE_URL = "https://api.razorpay.com/v1".freeze

      def create_checkout_session(amount:, currency:, description:, metadata:, callback_url:)
        response = post_json(
          "/orders",
          {
            amount: to_subunits(amount, currency),
            currency: currency,
            receipt: metadata[:quote_token].to_s,
            notes: metadata
          }
        )

        {
          key_id: @setting.api_key,
          order_id: response.fetch("id"),
          amount: response.fetch("amount"),
          currency: response.fetch("currency"),
          description: description,
          callback_url: callback_url
        }
      end

      def verify_client_callback(payment_response:)
        order_id = payment_response[:razorpay_order_id].to_s
        payment_id = payment_response[:razorpay_payment_id].to_s
        signature = payment_response[:razorpay_signature].to_s

        return failure("Missing callback payload.") if order_id.blank? || payment_id.blank? || signature.blank?
        return failure("Signature mismatch.") unless valid_callback_signature?(order_id:, payment_id:, signature:)

        payment = get_json("/payments/#{payment_id}")
        status = payment["status"].to_s

        if %w[captured authorized].include?(status)
          {
            status: "captured",
            external_reference: payment["id"],
            payment_method: payment["method"],
            amount: payment["amount"],
            currency: payment["currency"],
            metadata: payment["notes"] || {}
          }
        else
          failure("Payment is not successful (status: #{status}).")
        end
      rescue StandardError => e
        failure("Unable to verify payment: #{e.message}")
      end

      def verify_webhook(payload:, signature:)
        return false if @setting&.webhook_secret.blank? || signature.blank?

        computed_signature = OpenSSL::HMAC.hexdigest("SHA256", @setting.webhook_secret, payload)
        secure_compare(computed_signature, signature.to_s)
      end

      def handle_webhook(payload:)
        event_name = payload[:event].to_s
        payment_entity = payload.dig(:payload, :payment, :entity) || {}
        status = event_name == "payment.captured" || payment_entity[:status].to_s == "captured" ? "captured" : "failed"

        {
          external_reference: payment_entity[:id] || payload[:id],
          gateway_order_id: payment_entity[:order_id],
          payment_method: payment_entity[:method],
          status: status,
          amount: payment_entity[:amount],
          currency: payment_entity[:currency],
          metadata: (payment_entity[:notes] || {}).symbolize_keys
        }
      end

      private

      def valid_callback_signature?(order_id:, payment_id:, signature:)
        payload = "#{order_id}|#{payment_id}"
        expected_signature = OpenSSL::HMAC.hexdigest("SHA256", @setting.secret_key, payload)
        secure_compare(expected_signature, signature.to_s)
      end

      def secure_compare(a, b)
        ActiveSupport::SecurityUtils.secure_compare(a, b)
      rescue ArgumentError
        false
      end

      def to_subunits(amount, currency)
        case currency.to_s.upcase
        when "JPY"
          amount.to_i
        else
          (BigDecimal(amount.to_s) * 100).to_i
        end
      end

      def post_json(path, payload)
        request = Net::HTTP::Post.new(build_api_path(path), request_headers)
        request.body = payload.to_json
        parse_json_response(http_client.request(request))
      end

      def get_json(path)
        request = Net::HTTP::Get.new(build_api_path(path), request_headers)
        parse_json_response(http_client.request(request))
      end

      def build_api_path(path)
        base_path = URI(API_BASE_URL).path.to_s.sub(%r{/\z}, "")
        relative_path = path.to_s.start_with?("/") ? path.to_s : "/#{path}"
        "#{base_path}#{relative_path}"
      end

      def request_headers
        {
          "Content-Type" => "application/json",
          "Authorization" => "Basic #{Base64.strict_encode64("#{@setting.api_key}:#{@setting.secret_key}")}"
        }
      end

      def http_client
        @http_client ||= begin
          uri = URI(API_BASE_URL)
          client = Net::HTTP.new(uri.host, uri.port)
          client.use_ssl = true
          client.read_timeout = 10
          client.open_timeout = 5
          client
        end
      end

      def parse_json_response(response)
        body = JSON.parse(response.body)
        return body if response.is_a?(Net::HTTPSuccess)

        raise "Razorpay API error (#{response.code}): #{body['error']&.dig('description') || response.body}"
      end

      def failure(message)
        { status: "failed", message: message }
      end
    end
  end
end
