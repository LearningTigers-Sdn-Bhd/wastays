module Payments
  class BaseAdapter
    def initialize(setting = nil)
      @setting = setting
    end

    def create_intent(amount:, currency:, description:, metadata:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def verify_webhook(payload:, signature:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def handle_webhook(payload:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end
  end
end
