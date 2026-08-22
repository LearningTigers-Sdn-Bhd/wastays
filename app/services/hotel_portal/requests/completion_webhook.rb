# frozen_string_literal: true

module HotelPortal
  module Requests
    # Telling the outside world a request is finished.
    #
    # Each kind spells finished differently, and only that transition is worth
    # announcing -- moving work back or between open statuses is the hotel's own
    # business.
    class CompletionWebhook
      FINISHED_STATUS = {
        "housekeeping" => "completed",
        "complaint" => "resolved",
        "checkout" => "completed"
      }.freeze

      def self.broadcast(request:, kind:, from:, to:)
        new(request: request, kind: kind.to_s, from: from.to_s, to: to.to_s).broadcast
      end

      def initialize(request:, kind:, from:, to:)
        @request = request
        @kind = kind
        @from = from
        @to = to
      end

      def broadcast
        return unless finished?

        WebhookBroadcastJob.perform_later("#{kind}_#{to}", payload, hotel_id: hotel_id)
      end

      private

      attr_reader :request, :kind, :from, :to

      def finished?
        from != to && FINISHED_STATUS[kind] == to
      end

      # Which hotel this belongs to, by the same two routes the payload takes:
      # the booking normally, the request itself for the kinds that carry one.
      def hotel_id
        request.booking&.hotel_id || (request.hotel_id if request.respond_to?(:hotel_id))
      end

      def payload
        booking = request.booking

        {
          request_id: request.id,
          external_id: external_id,
          kind: kind,
          status: to,
          completed_at: request.completed_at,
          booking_id: request.booking_id,
          confirmation_token: booking&.confirmation_token,
          guest_name: booking&.guest_name,
          guest_phone: booking&.guest_phone,
          hotel_name: booking&.hotel&.name || (request.hotel&.name if request.respond_to?(:hotel))
        }
      end

      # A checkout has no external_id column; the one it was created with, if
      # any, travels in its metadata.
      def external_id
        return request.external_id if request.respond_to?(:external_id)

        request.metadata.to_h["external_id"]
      end
    end
  end
end
