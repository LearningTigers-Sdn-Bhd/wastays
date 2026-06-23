module Payments
  class GatewayRegistry
    class UnsupportedGatewayError < StandardError; end

    def self.fetch(gateway:, setting:)
      normalized_gateway = gateway.to_s.downcase

      case normalized_gateway
      when "razorpay"
        Payments::GatewayAdapters::Razorpay.new(setting)
      when "curlec"
        Payments::GatewayAdapters::Curlec.new(setting)
      when "cute_mock"
        Payments::GatewayAdapters::Mock.new(setting)
      else
        raise UnsupportedGatewayError, "Unsupported gateway: #{gateway}"
      end
    end
  end
end
