# frozen_string_literal: true

module Notifications
  module Channels
    class Email
      def initialize(delivery:)
        @delivery = delivery
      end

      def call
        NotificationMailer.check_in_confirmation(@delivery).deliver_now
      end
    end
  end
end
