# frozen_string_literal: true

module Notifications
  module Channels
    class Email
      MAILERS = {
        "check_in_confirmation" => :check_in_confirmation,
        "post_stay_review_request" => :post_stay_review_request,
        "pre_arrival_notification" => :pre_arrival_notification,
        "check_out_receipt_message" => :check_out_receipt_message
      }.freeze

      def initialize(delivery:)
        @delivery = delivery
      end

      def call
        NotificationMailer.public_send(mailer_method, @delivery).deliver_now
      end

      private

      def mailer_method
        MAILERS.fetch(@delivery.notification_type)
      end
    end
  end
end
