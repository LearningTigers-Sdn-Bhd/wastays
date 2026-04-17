module Payments
  class CredentialSetting
    Setting = Struct.new(:gateway, :api_key, :secret_key, :webhook_secret, :status, keyword_init: true)

    class << self
      def for_gateway(gateway)
        return if gateway.blank?

        normalized_gateway = gateway.to_s.downcase
        config = gateway_config(normalized_gateway)
        return if config.blank?

        build_setting(normalized_gateway, config)
      end

      def default
        default_gateway = credentials.dig(:payments, :default, :gateway) ||
          credentials.dig(:payments, :default_gateway)
        return if default_gateway.blank?

        for_gateway(default_gateway)
      end

      private

      def build_setting(gateway, raw_config)
        config = raw_config.to_h.symbolize_keys
        api_key = config[:api_key] || config[:key_id]
        secret_key = config[:secret_key] || config[:key_secret]
        webhook_secret = config[:webhook_secret]

        return if api_key.blank? || secret_key.blank?

        Setting.new(
          gateway: gateway,
          api_key: api_key,
          secret_key: secret_key,
          webhook_secret: webhook_secret,
          status: "active"
        )
      end

      def gateway_config(gateway)
        credentials.dig(:payments, :gateways, gateway.to_sym) ||
          credentials.dig(:payments, gateway.to_sym)
      end

      def credentials
        Rails.application.credentials
      end
    end
  end
end
