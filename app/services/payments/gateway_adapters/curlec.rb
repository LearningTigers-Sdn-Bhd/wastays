module Payments
  module GatewayAdapters
    class Curlec < Payments::BaseAdapter
      def create_intent(amount:, currency:, description:, metadata:)
        # In a real integration:
        # curlec_client = Curlec::Client.new(api_key: @setting.api_key, secret_key: @setting.secret_key)
        # response = curlec_client.create_intent(...)

        {
          id: "curlec_intent_#{SecureRandom.hex(8)}",
          amount: amount,
          currency: currency,
          status: "created",
          checkout_url: "/mock_payment_gateway?intent_id=#{SecureRandom.hex(8)}"
        }
      end

      def verify_webhook(payload:, signature:)
        return true if Rails.env.development? || Rails.env.test? # For mock/local
        return false unless @setting&.webhook_secret

        # Real verification logic:
        # OpenSSL::HMAC.hexdigest('sha256', @setting.webhook_secret, payload) == signature
        true
      end

      def handle_webhook(payload:)
        {
          external_reference: payload[:id],
          status: payload[:status] == "captured" ? "captured" : "failed",
          amount: payload[:amount],
          currency: payload[:currency],
          metadata: payload[:metadata]
        }
      end
    end
  end
end
